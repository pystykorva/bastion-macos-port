import SwiftUI
import TessuCore

struct AgentsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var prefs = Preferences.shared
    @State private var draft = ""
    @FocusState private var focused: Bool

    private static let quick = ["What should I fix first?", "Is anything on my network suspicious?", "Why is my Wi-Fi slow?"]

    private var usable: [ProviderInfo] { Chat.usable(state.providers) }
    private var info: ProviderInfo? { state.providers.first { $0.id == prefs.provider } }
    private var ready: Bool { info?.hasKey == true }
    private var busy: Bool { state.asking.contains(prefs.provider) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            AgentLog(provider: prefs.provider)
            Divider()
            composer
        }
        .task { await state.loadProviders() }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agents").font(.largeTitle.weight(.semibold))
                    Text("Ask Claude, ChatGPT, Grok, OpenRouter or a model on your own computer about your network. They only answer: they cannot change anything.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) { state.watch.clearLog() } label: { Label("Clear chat", systemImage: "trash") }
                    .disabled(state.watch.log.isEmpty)
            }
            HStack(spacing: 14) {
                Picker("Agent", selection: $prefs.provider) {
                    ForEach(usable) { p in Label(p.id.tab + (p.id.isCLI ? " · plan" : ""), systemImage: "circle.fill").tag(p.id) }
                    if !usable.contains(where: { $0.id == prefs.provider }) { Text(prefs.provider.name).tag(prefs.provider) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 440).labelsHidden()
                statusLine
                Spacer()
                WatchControls()
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    @ViewBuilder private var statusLine: some View {
        if state.providers.isEmpty {
            Text("Checking your keys…").font(.caption).foregroundStyle(.secondary)
        } else if let i = info {
            if i.hasKey {
                Label(i.id.isCLI ? "\(i.cli?.product ?? "CLI") · \(i.model)" : "Key saved · \(i.model)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Theme.color(.ok))
            } else {
                HStack(spacing: 6) {
                    Text(Chat.notReadyText(i.id, i)).font(.caption).foregroundStyle(.secondary)
                    Button("Settings") { state.selection = .settings }.buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    // MARK: composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.watch.log.isEmpty {
                HStack { ForEach(Self.quick, id: \.self) { q in Button(q) { send(q) }.buttonStyle(.bordered).disabled(!ready || busy) } }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about your network…", text: $draft, axis: .vertical)
                    .lineLimit(1...5).textFieldStyle(.roundedBorder).focused($focused)
                    .onSubmit { send(draft) }
                    .disabled(busy)
                if busy {
                    Button { state.agents.cancel(prefs.provider) } label: { Label("Stop", systemImage: "stop.fill") }
                } else {
                    Button { send(draft) } label: { Label("Send", systemImage: "arrow.up.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(!ready || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            Text("Each question sends your question and a privacy-minimized snapshot: no Wi-Fi names, device names or full MAC addresses. Settings shows exactly what.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, ready, !busy else { return }
        draft = ""
        Task { await Chat.ask(state, prefs.provider, q) }
    }
}
