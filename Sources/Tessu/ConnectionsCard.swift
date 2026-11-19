import SwiftUI
import TessuCore

/// This computer's live connections, grouped by program. The programs talking to the most outside hosts
/// come first, so "what is my Mac sending to the internet" is the first thing visible.
struct ConnectionsCard: View {
    @EnvironmentObject var state: AppState
    var query: String
    @State private var hideLocal = true
    @State private var open: Set<String> = []
    private static let preview = 8

    private var list: [Connection] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return (state.connections?.items ?? []).filter { c in
            let scope = ConnectionScope.of(c.remoteIp)
            if scope == .none { return false }
            if hideLocal && (scope == .loopback || scope == .lan || scope == .multicast) { return false }
            guard !q.isEmpty else { return true }
            let hay = [c.process, ConnectionGroup.displayName(c.process), String(c.pid), c.remoteIp, String(c.remotePort), c.state, c.local, PortNames.names[c.remotePort]]
            return hay.compactMap { $0 }.joined(separator: " ").lowercased().contains(q)
        }
    }

    var body: some View {
        let groups = ConnectionGroup.group(list)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: "This computer's connections", detail: state.connections == nil ? nil : "\(list.count) shown")
                    Toggle("Hide local and loopback", isOn: $hideLocal).toggleStyle(.switch).controlSize(.small)
                }
                if state.connections == nil {
                    HStack { ProgressView().controlSize(.small); Text("Reading connections…").foregroundStyle(.secondary) }
                } else if groups.isEmpty {
                    EmptyNote(text: "No connections match.", symbol: "network")
                } else {
                    ForEach(groups) { g in group(g) }
                }
                if let e = state.connections?.errors.first { Text(e).font(.caption).foregroundStyle(.tertiary) }
            }
        }
    }

    @ViewBuilder private func group(_ g: ConnectionGroup) -> some View {
        let isOpen = open.contains(g.id)
        let shown = isOpen ? g.items : Array(g.items.prefix(Self.preview))
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "app.dashed").foregroundStyle(Theme.lavender)
                Text(g.name).font(.body.weight(.medium))
                Text(g.pids.count > 3 ? "\(g.pids.count) processes" : g.pids.map { "PID \($0)" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if g.internetCount > 0 { Tag(text: "\(g.internetCount) to the internet") }
                Text("\(g.items.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(shown) { c in
                HStack(spacing: 8) {
                    Text(c.proto.uppercased()).font(.caption2.monospaced()).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                    Text(c.state == "LISTEN" ? "listening on \(c.local)" : "\(c.remoteIp):\(c.remotePort)")
                        .font(.callout.monospaced()).textSelection(.enabled)
                    if let n = PortNames.names[c.remotePort] { Text(n).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text(ConnectionScope.of(c.remoteIp) == .internet ? "internet" : c.state == "LISTEN" ? "open port" : "local")
                        .font(.caption2).foregroundStyle(ConnectionScope.of(c.remoteIp) == .internet ? Theme.lavender : .secondary)
                }.padding(.leading, 24)
            }
            if g.items.count > Self.preview {
                Button(isOpen ? "Show fewer" : "Show all \(g.items.count)") {
                    if isOpen { open.remove(g.id) } else { open.insert(g.id) }
                }.buttonStyle(.link).padding(.leading, 24)
            }
            Divider()
        }
    }
}
