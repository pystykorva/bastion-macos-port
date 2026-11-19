import SwiftUI
import TessuCore

extension HomeView {
    /// The findings that need action, most urgent first, each with a button that opens the Shield.
    var attention: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Needs your attention", detail: nil)
                if let r = report {
                    let items = Verdict.ranked(r.checks)
                    if items.isEmpty {
                        EmptyNote(text: "Nothing needs attention right now.", symbol: "checkmark.circle")
                    } else {
                        ForEach(items.prefix(5)) { c in
                            Button { state.selection = .shield } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: Theme.symbol(c.status)).foregroundStyle(Theme.color(c.status)).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.title).font(.body.weight(.medium))
                                        Text(c.fix?.label ?? c.evidence).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                    StatusPill(status: c.status, severity: nil)
                                }
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                        if items.count > 5 { Button("See all \(items.count) findings") { state.selection = .shield }.buttonStyle(.link) }
                    }
                } else {
                    EmptyNote(text: state.scanning ? "Scanning…" : "Run a scan to see what needs attention.", symbol: "magnifyingglass")
                }
            }
        }
    }

    var speedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Speed", detail: state.speed.map { $0.at.formatted(date: .omitted, time: .shortened) })
                HStack(spacing: 18) {
                    Figure(label: "Download", value: state.speed?.downMbps, unit: "Mbps")
                    Figure(label: "Upload", value: state.speed?.upMbps, unit: "Mbps")
                    Figure(label: "Ping", value: state.speed?.pingMs, unit: "ms")
                }
                Button { state.selection = .speed } label: { Label("Open Speed & Wi-Fi", systemImage: "gauge.with.dots.needle.67percent") }
            }
        }
    }

    var routerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "Router", detail: nil)
                row("Address", state.overview?.gateway.ip ?? "–")
                row("Maker", state.overview?.gateway.vendor ?? "unknown")
                row("Your address", state.overview?.local.ip ?? "–")
                row("Public IP", state.overview?.publicIp ?? "not available")
                Button { Task { await state.openFix(.routerAdmin) } } label: { Label("Open router settings", systemImage: "arrow.up.forward.app") }
                    .disabled(state.overview?.gateway.ip == nil)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary).frame(width: 96, alignment: .leading); Text(v).textSelection(.enabled); Spacer() }.font(.callout)
    }

    /// Ask an agent without leaving Home; the answer is in the Agents screen.
    var askBar: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Ask an agent", detail: nil)
                HStack {
                    Picker("Agent", selection: Binding(get: { Preferences.shared.provider }, set: { Preferences.shared.provider = $0 })) {
                        ForEach(Chat.usable(state.providers)) { Text($0.id.tab + ($0.id.isCLI ? " · plan" : "")).tag($0.id) }
                    }.labelsHidden().frame(width: 190)
                    TextField("What should I fix first?", text: $question).textFieldStyle(.roundedBorder).focused($askFocused).onSubmit(send)
                    Button("Ask", action: send).buttonStyle(.borderedProminent)
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || state.providers.first { $0.id == Preferences.shared.provider }?.hasKey != true)
                }
                if Chat.auto(state.providers) == nil {
                    HStack(spacing: 6) {
                        Text("No AI is connected yet.").font(.caption).foregroundStyle(.secondary)
                        Button("Add a key or sign in") { state.selection = .settings }.buttonStyle(.link).font(.caption)
                    }
                }
            }
        }
    }

    private func send() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        question = ""
        state.selection = .agents
        Task { await Chat.ask(state, Preferences.shared.provider, q) }
    }
}
