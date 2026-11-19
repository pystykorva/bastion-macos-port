import SwiftUI
import TessuCore

struct ShieldView: View {
    @EnvironmentObject var state: AppState
    @State private var highlight: String?
    @State private var expanded: Set<String> = []

    private var beacons: [RadarBeacon] {
        RadarModel.beacons(report: state.scan, progress: state.scanProgress, scanning: state.scanning)
    }

    var body: some View {
        Page(title: "Shield", subtitle: "What a visitor on your network could reach on your router.") {
            if state.scanning {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await state.runScan() } } label: { Label("Scan again", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent)
            }
        } content: {
            if state.scan?.errors.contains(LocalNetwork.blockedMessage) == true { LocalNetworkBanner(text: LocalNetwork.blockedMessage) }
            HStack(alignment: .top, spacing: 18) {
                radarCard.frame(maxWidth: 440)
                VStack(spacing: 14) {
                    ScoreCard()
                    Legend()
                }
                .frame(maxWidth: .infinity)
            }
            findings
            if let r = state.scan, !state.scanning { ExposureDetails(report: r) }
            notes
        }
    }

    private var radarCard: some View {
        Card(padding: 12) {
            VStack(spacing: 6) {
                ExposureRadar(beacons: beacons, scanning: state.scanning, highlight: $highlight) { id in
                    withAnimation { expanded.insert(id) }
                    highlight = id
                }
                Text("Closer to the rim = more reachable. Shape and colour show the status.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    // MARK: findings list

    @ViewBuilder private var findings: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Checks", detail: summary)
            if let e = state.scanError, state.scan?.checks.isEmpty != false {
                EmptyNote(text: e, symbol: "exclamationmark.triangle")
            }
            if let report = state.scan, !state.scanning, !report.checks.isEmpty {
                ForEach(Verdict.ranked(report.checks) + report.checks.filter { $0.status == .ok }) { c in
                    CheckRow(check: c, expanded: expanded.contains(c.id), highlighted: highlight == c.id) {
                        withAnimation(.snappy) { toggle(c.id) }
                    }
                    .onHover { inside in
                        if inside { highlight = c.id } else if highlight == c.id { highlight = nil }
                    }
                }
            } else {
                ForEach(Scan.checks, id: \.id) { def in
                    PendingRow(title: def.title, progress: state.scanProgress[def.id])
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private var summary: String? {
        if state.scanning { return "Scanning…" }
        guard let r = state.scan, !r.checks.isEmpty else { return nil }
        let n = Dictionary(grouping: r.checks, by: \.status).mapValues(\.count)
        return "\(n[.risk] ?? 0) open · \(n[.warn] ?? 0) to review · \(n[.unknown] ?? 0) unknown · \(n[.ok] ?? 0) sealed"
    }

    @ViewBuilder private var notes: some View {
        if let r = state.scan, !r.errors.isEmpty, !state.scanning {
            DisclosureGroup("Scan notes · \(r.errors.count)") {
                if state.prefs.advancedEvidence {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(r.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                } else {
                    Text("Turn on “Show advanced evidence” in Settings to see them.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
    }
}

struct LocalNetworkBanner: View {
    @EnvironmentObject var state: AppState
    var text: String
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "network.badge.shield.half.filled").font(.title2).foregroundStyle(Theme.color(.warn))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allow Tessu to see your network").font(.headline)
                    Text(text).font(.callout).foregroundStyle(.secondary)
                    Button("Open Local Network settings") { state.openLocalNetworkSettings() }
                }
            }
        }
    }
}
