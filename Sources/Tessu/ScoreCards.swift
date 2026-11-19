import SwiftUI
import TessuCore

/// The score as a 270-degree arc with the verdict beside it.
struct ScoreCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Card {
            HStack(spacing: 18) {
                ScoreArc(score: state.scan?.score, color: verdict?.color ?? .secondary, busy: state.scanning)
                    .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verdict?.headline ?? (state.scanning ? "Scanning…" : "Not scanned yet")).font(.title3.weight(.semibold))
                    Text(blurb).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let r = state.scan {
                        Text("Last scan \(r.finishedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var verdict: Verdict? { state.scan.flatMap { $0.checks.isEmpty ? nil : Verdict.of($0) } }

    private var blurb: String {
        guard let r = state.scan, !r.checks.isEmpty else { return "Tessu checks your router from the inside and explains each finding." }
        switch Verdict.of(r).level {
        case .clear: return "Every door Tessu can test is closed. It cannot see everything: some checks need the router's own settings."
        case .blind: return "The router did not answer, so Tessu cannot say which doors are open. A VPN or Wi-Fi isolation can cause this."
        case .review: return "No critical door is open, but \(Verdict.untestedDoors(r.checks)) of 5 doors are not confirmed closed, or something needs a look."
        case .danger: return "At least one important door is open. Start with the first finding below."
        }
    }
}

struct ScoreArc: View {
    var score: Int?
    var color: Color
    var busy: Bool

    private let start = 135.0, sweep = 270.0

    var body: some View {
        ZStack {
            arc(1).stroke(.quaternary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            arc(Double(score ?? 0) / 100).stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .animation(.easeOut(duration: 0.6), value: score)
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "–").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("of 100").font(.caption2).foregroundStyle(.secondary)
            }
            if busy { ProgressView().controlSize(.small).offset(y: 46) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "Score \($0) out of 100" } ?? "No score yet")
    }

    private func arc(_ fraction: Double) -> Path {
        Path { p in
            p.addArc(center: CGPoint(x: 60, y: 60), radius: 52, startAngle: .degrees(start),
                     endAngle: .degrees(start + sweep * max(0.0001, min(1, fraction))), clockwise: false)
        }
    }
}

struct Legend: View {
    private let items: [(CheckStatus, String)] = [
        (.risk, "A door is open or a setting is unsafe"),
        (.warn, "Worth a look; not urgent"),
        (.unknown, "Tessu cannot see this from your computer"),
        (.ok, "Checked and closed"),
    ]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.0) { status, text in
                    HStack(spacing: 10) {
                        Image(systemName: Theme.symbol(status)).foregroundStyle(Theme.color(status)).frame(width: 22)
                        Text(Theme.word(status)).font(.callout.weight(.semibold)).frame(width: 60, alignment: .leading)
                        Text(text).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
