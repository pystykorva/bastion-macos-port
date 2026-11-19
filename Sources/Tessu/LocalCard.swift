import SwiftUI
import TessuCore

/// "Local server": LM Studio, Ollama, llama.cpp, vLLM, Jan, or anything else that speaks the OpenAI chat API.
struct LocalCard: View {
    @EnvironmentObject var state: AppState
    @State private var address = ""
    @State private var key = ""
    @State private var models: [String] = []
    @State private var note: ProviderNote?
    @State private var busy = false
    @State private var customModel = ""
    @State private var confirmRemote = false
    @State private var suffix = ""

    private var agents: Agents { state.agents }
    private var info: ProviderInfo? { state.providers.first { $0.id == .local } }
    private var remote: Bool { LocalServer.validate(address).url != nil && !LocalServer.validate(address).loopback }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Local server", detail: nil)
                Text("Use a model running on this Mac through LM Studio, Ollama, llama.cpp, vLLM or any server with an OpenAI-style API. Questions never leave your computer.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    ForEach(LocalServer.presets, id: \.name) { p in
                        Button(p.name) { address = p.url; note = nil }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                HStack {
                    TextField("http://localhost:1234/v1", text: $address).textFieldStyle(.roundedBorder).onSubmit(save)
                    Button("Save", action: save).disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if remote { RemoteWarning(host: LocalServer.validate(address).url?.host ?? "") }
                HStack {
                    SecureField("API key (only if your server needs one)", text: $key).textFieldStyle(.roundedBorder)
                    Button("Save key") { saveKey() }.disabled(key.isEmpty)
                    if agents.keystore.hasKey(ProviderID.local.rawValue) { Button("Remove key", role: .destructive) { removeKey() } }
                }
                HStack {
                    Picker("Model", selection: Binding(get: { info?.model ?? "default" }, set: { setModel($0) })) {
                        Text("Whatever is loaded").tag("default")
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                        if let m = info?.model, m != "default", !models.contains(m) { Text(m).tag(m) }
                    }.frame(maxWidth: 420)
                    TextField("or type a model id", text: $customModel).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                        .onSubmit { setModel(customModel); customModel = "" }
                    Button { Task { await refreshModels() } } label: { Image(systemName: "arrow.clockwise") }.help("Reload the model list")
                    Button(busy ? "Testing…" : "Test") { Task { await test() } }.disabled(busy)
                }
                HStack {
                    TextField("Extra text added to every question, e.g. /no_think for Qwen", text: $suffix).textFieldStyle(.roundedBorder)
                        .onChange(of: suffix) { _, v in agents.keystore.localSuffix = v }
                }
                NoteLine(note: note)
                Text("Small models are less reliable than the big cloud ones at citing checks, saying “unknown” and ignoring odd text from devices. Reasoning models can take minutes per answer. Tessu sends a shorter snapshot to local models so it fits a small context window.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .onAppear { address = agents.localAddress; suffix = agents.keystore.localSuffix; Task { await refreshModels() } }
        .confirmationDialog("Send questions to \(LocalServer.validate(address).url?.host ?? "this server")?", isPresented: $confirmRemote) {
            Button("Allow this server") { commit(approve: true) }
        } message: {
            Text("This server is not on this Mac. Your question and a snapshot without Wi-Fi names, device names or MAC addresses would travel across the network to it.")
        }
    }

    private func save() {
        if remote { confirmRemote = true } else { commit(approve: false) }
    }

    private func commit(approve: Bool) {
        if let err = agents.setLocalAddress(address, approveRemote: approve) { note = ProviderNote(ok: false, text: err); return }
        address = agents.localAddress
        note = ProviderNote(ok: true, text: "Address saved.")
        Task { await state.loadProviders(); await refreshModels() }
    }

    private func saveKey() {
        let err = agents.setKey(.local, key)
        note = ProviderNote(ok: err == nil, text: err ?? "Key saved in the Keychain.")
        if err == nil { key = "" }
    }

    private func removeKey() {
        let err = agents.clearKey(.local)
        note = ProviderNote(ok: err == nil, text: err ?? "Key removed.")
    }

    private func setModel(_ m: String) {
        guard !m.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if m == "default" { agents.keystore.setModel(ProviderID.local.rawValue, "default") }
        else if let err = agents.setModel(.local, m) { note = ProviderNote(ok: false, text: err) }
        Task { await state.loadProviders() }
    }

    private func refreshModels() async {
        let r = await agents.localModels()
        models = r.models
        if let e = r.error, info?.hasKey == true { note = ProviderNote(ok: false, text: e) }
    }

    private func test() async {
        busy = true; note = nil
        if info?.hasKey != true { commit(approve: false) }
        let r = await agents.test(.local)
        note = ProviderNote(ok: r.ok, text: r.ok ? "Works. The server answered with \(r.model)." : (r.error ?? "The test failed."))
        busy = false
        await refreshModels()
    }
}

struct RemoteWarning: View {
    var host: String
    var body: some View {
        Label("\(host) is not on this Mac. Questions would leave it, so you will be asked to confirm.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(Theme.color(.warn))
    }
}
