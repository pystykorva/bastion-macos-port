import SwiftUI
import TessuCore

/// API keys, one per provider. A saved key is never shown again.
struct KeysCard: View {
    @EnvironmentObject var state: AppState
    @State private var drafts: [ProviderID: String] = [:]
    @State private var notes: [ProviderID: ProviderNote] = [:]
    @State private var testing: ProviderID?
    @State private var customModel: [ProviderID: String] = [:]

    private var apis: [ProviderInfo] { state.providers.filter { !$0.id.isCLI && $0.id != .local } }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "AI providers", detail: nil)
                Text("Or use your own API key. It is stored in the macOS Keychain and sent only to that provider.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(apis) { p in row(p) }
            }
        }
    }

    @ViewBuilder private func row(_ p: ProviderInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Theme.providerColor(p.id)).frame(width: 10, height: 10)
                Text(p.id.name).font(.headline)
                Text(p.id.vendor).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Tag(text: p.hasKey ? "key saved" : "no key")
            }
            HStack {
                SecureField(p.hasKey ? "Replace key…" : "Paste API key", text: draft(p.id)).textFieldStyle(.roundedBorder)
                Button("Save") { save(p.id) }.disabled((drafts[p.id] ?? "").isEmpty)
                if p.hasKey { Button("Remove", role: .destructive) { remove(p.id) } }
                if let url = p.id.keyPage { Link("Get a key", destination: url).font(.callout) }
            }
            HStack {
                Picker("Model", selection: Binding(get: { p.model }, set: { setModel(p.id, $0) })) {
                    ForEach(p.models, id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 320)
                TextField("or type a model", text: custom(p.id)).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    .onSubmit { setModel(p.id, customModel[p.id] ?? ""); customModel[p.id] = "" }
                Button(testing == p.id ? "Testing…" : "Test") { Task { await test(p.id) } }.disabled(!p.hasKey || testing != nil)
            }
            NoteLine(note: notes[p.id])
        }
        Divider()
    }

    private func draft(_ id: ProviderID) -> Binding<String> { Binding(get: { drafts[id] ?? "" }, set: { drafts[id] = $0 }) }
    private func custom(_ id: ProviderID) -> Binding<String> { Binding(get: { customModel[id] ?? "" }, set: { customModel[id] = $0 }) }

    private func save(_ id: ProviderID) {
        let err = state.agents.setKey(id, drafts[id] ?? "")
        notes[id] = ProviderNote(ok: err == nil, text: err ?? "Key saved in the Keychain.")
        if err == nil { drafts[id] = "" }
        Task { await state.loadProviders() }
    }

    private func remove(_ id: ProviderID) {
        let err = state.agents.clearKey(id)
        notes[id] = ProviderNote(ok: err == nil, text: err ?? "Key removed.")
        Task { await state.loadProviders() }
    }

    private func setModel(_ id: ProviderID, _ model: String) {
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let err = state.agents.setModel(id, model) { notes[id] = ProviderNote(ok: false, text: err) }
        Task { await state.loadProviders() }
    }

    private func test(_ id: ProviderID) async {
        testing = id; notes[id] = nil
        let r = await state.agents.test(id)
        notes[id] = ProviderNote(ok: r.ok, text: r.ok ? "Works. Answered with \(r.model)." : (r.error ?? "The test failed."))
        testing = nil
    }
}
