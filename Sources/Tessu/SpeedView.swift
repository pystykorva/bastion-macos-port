import SwiftUI
import TessuCore

struct SpeedView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Page(title: "Speed & Wi-Fi", subtitle: "How fast the connection is, and how crowded your Wi-Fi channel is.") {
            EmptyView()
        } content: {
            HStack(alignment: .top, spacing: 18) {
                SpeedTestCard().frame(maxWidth: 420)
                VStack(spacing: 14) {
                    WifiLinkCard()
                    HistoryCard()
                }.frame(maxWidth: .infinity)
            }
            ChannelsCard()
        }
    }
}

private struct SpeedTestCard: View {
    @EnvironmentObject var state: AppState

    private var live: Double? {
        guard let p = state.speedProgress else { return nil }
        return p.phase == .ping ? nil : p.mbps
    }
    private var phaseText: String {
        guard state.speedRunning else { return state.speed == nil ? "Not measured yet" : "Last result" }
        switch state.speedProgress?.phase {
        case .ping: return "Measuring latency…"
        case .download: return "Download"
        case .upload: return "Upload"
        default: return "Starting…"
        }
    }

    var body: some View {
        Card {
            VStack(spacing: 14) {
                SpeedGauge(value: state.speedRunning ? live : state.speed?.downMbps, phase: phaseText,
                           running: state.speedRunning, tint: tint)
                if state.speedRunning, let p = state.speedProgress { ProgressView(value: p.progress).frame(maxWidth: 260) }
                HStack(spacing: 22) {
                    Figure(label: "Download", value: state.speed?.downMbps, unit: "Mbps")
                    Figure(label: "Upload", value: state.speed?.upMbps, unit: "Mbps")
                    Figure(label: "Ping", value: state.speed?.pingMs, unit: "ms")
                    Figure(label: "Jitter", value: state.speed?.jitterMs, unit: "ms")
                }
                if state.speedRunning {
                    Button("Stop") { state.cancelSpeed() }
                } else {
                    Button { Task { await state.runSpeed() } } label: { Label(state.speed == nil ? "Run speed test" : "Run again", systemImage: "gauge.with.dots.needle.67percent") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                if let s = state.speed {
                    Text("\(s.server) · \(s.at.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    ForEach(s.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.color(.warn)).multilineTextAlignment(.center) }
                }
                Text("Uses speed.cloudflare.com. Transfers up to about 150 MB.").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var tint: Color { state.speedProgress?.phase == .upload ? Theme.lavender : Theme.accent }
}

/// A measured number, or an honest dash. Never a made-up zero.
struct Figure: View {
    var label: String
    var value: Double?
    var unit: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value.map(SpeedGauge.format) ?? "–").font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(unit).font(.caption2).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value.map(SpeedGauge.format) ?? "not measured") \(value == nil ? "" : unit)")
    }
}

private struct HistoryCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "History", detail: state.speedHistory.isEmpty ? nil : "last \(state.speedHistory.count)")
                if state.speedHistory.isEmpty {
                    EmptyNote(text: "Run a test and the results are listed here.", symbol: "clock")
                } else {
                    ForEach(state.speedHistory.prefix(8)) { r in
                        HStack {
                            Text(r.at.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Text("↓ \(r.downMbps.map(SpeedGauge.format) ?? "–")").monospacedDigit()
                            Text("↑ \(r.upMbps.map(SpeedGauge.format) ?? "–")").monospacedDigit()
                            Text("\(r.pingMs.map(SpeedGauge.format) ?? "–") ms").monospacedDigit().foregroundStyle(.secondary)
                        }.font(.callout)
                    }
                }
            }
        }
    }
}
