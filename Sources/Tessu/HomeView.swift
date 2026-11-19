import SwiftUI
import TessuCore

/// The verdict at a glance. The original opened on a 3D router scene; here the same four facts it
/// conveyed (threat level, Wi-Fi signal, which agents are ready, shield state) are plain readouts.
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State var question = ""
    @FocusState var askFocused: Bool

    var report: ScanReport? { state.scan.flatMap { $0.checks.isEmpty ? nil : $0 } }
    private var verdict: Verdict? { report.map(Verdict.of) }

    var body: some View {
        Page(title: "Home", subtitle: subtitle) {
            Button { Task { await state.runScan() } } label: { Label(state.scanning ? "Scanning…" : "Scan now", systemImage: "arrow.clockwise") }
                .buttonStyle(.borderedProminent).disabled(state.scanning)
        } content: {
            if state.scan?.errors.contains(LocalNetwork.blockedMessage) == true { LocalNetworkBanner(text: LocalNetwork.blockedMessage) }
            hero
            HStack(alignment: .top, spacing: 14) {
                attention
                VStack(spacing: 14) { speedCard; routerCard }.frame(maxWidth: 360)
            }
            askBar
        }
    }

    private var subtitle: String {
        if let name = state.overview?.hostname, !name.isEmpty { return "\(name) · checked from inside your network" }
        return "Checked from inside your network"
    }

    // MARK: hero

    private var hero: some View {
        Card(padding: 22) {
            HStack(spacing: 24) {
                ScoreArc(score: report?.score, color: verdict?.color ?? .secondary, busy: state.scanning)
                    .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: state.scanning ? "hourglass" : (verdict?.symbol ?? "questionmark.shield"))
                            .foregroundStyle(state.scanning ? .secondary : (verdict?.color ?? .secondary))
                        Text(state.scanning ? "Scanning your router…" : (verdict?.headline ?? "Not scanned yet")).font(.title.weight(.semibold))
                    }
                    Text(blurb).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if state.scanning { ProgressView(value: Double(state.scanProgress.values.filter { $0.status != nil }.count), total: Double(Scan.checks.count)).frame(maxWidth: 320) }
                    HStack(spacing: 14) { wifiChip; shieldChip; agentChip }.padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var blurb: String {
        guard let r = report else { return "Tessu checks the doors into your home network and explains each finding in plain language." }
        let open = r.checks.filter { $0.status == .risk }.count
        let review = r.checks.filter { $0.status == .warn }.count
        let unknown = r.checks.filter { $0.status == .unknown }.count
        return "\(open) open · \(review) to review · \(unknown) not confirmable from this Mac · \(r.checks.filter { $0.status == .ok }.count) sealed."
    }

    private var wifiChip: some View {
        let w = state.wifi
        let pct = w?.signalPct
        return Chip(symbol: pct == nil ? "wifi.slash" : "wifi", text: pct.map { "Wi-Fi \($0)%" } ?? "Wi-Fi not measured",
                    tint: pct.map { $0 >= 60 ? Theme.color(.ok) : $0 >= 35 ? Theme.color(.warn) : Theme.color(.risk) } ?? .secondary)
    }

    private var shieldChip: some View {
        let d = report.map { Verdict.doors($0.checks) }
        let text: String
        switch d {
        case .some(.closed): text = "5 of 5 doors closed"
        case .some(.blind): text = "Doors not testable"
        case .some(.partial): text = "\(5 - Verdict.untestedDoors(report!.checks)) of 5 doors confirmed closed"
        case .none: text = "Doors not tested yet"
        }
        return Chip(symbol: "door.left.hand.closed", text: text, tint: d == .some(.closed) ? Theme.color(.ok) : .secondary)
    }

    private var agentChip: some View {
        let ready = state.providers.filter(\.hasKey)
        return Chip(symbol: "sparkles", text: ready.isEmpty ? "No AI connected" : ready.map { $0.id.tab }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: ", "),
                    tint: ready.isEmpty ? .secondary : Theme.lavender)
    }
}

struct Chip: View {
    var symbol: String
    var text: String
    var tint: Color
    var body: some View {
        Label(text, systemImage: symbol).font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule()).foregroundStyle(tint)
    }
}
