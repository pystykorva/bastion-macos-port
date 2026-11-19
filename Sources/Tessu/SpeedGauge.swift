import SwiftUI
import TessuCore

/// Speed gauge over a 270-degree arc. The scale is piecewise-linear (stops spaced evenly round the arc),
/// so typical home speeds use most of the dial instead of crowding into the first few degrees.
enum GaugeScale {
    static let stops: [Double] = [0, 100, 200, 500, 750, 1000]
    static let labels = ["0", "100", "200", "500", "750", "1G"]

    /// 0...1 position of a value on the dial.
    static func fraction(_ v: Double?) -> Double {
        guard let v = v, v.isFinite else { return 0 }
        let x = max(0, min(1000, v))
        for i in 1..<stops.count where x <= stops[i] {
            return (Double(i - 1) + (x - stops[i - 1]) / (stops[i] - stops[i - 1])) / Double(stops.count - 1)
        }
        return 1
    }
}

struct SpeedGauge: View {
    var value: Double?
    var phase: String
    var running: Bool
    var tint: Color

    private let start = 135.0, sweep = 270.0

    var body: some View {
        ZStack {
            arc(1).stroke(.quaternary, style: StrokeStyle(lineWidth: 14, lineCap: .round))
            arc(GaugeScale.fraction(value)).stroke(tint.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .animation(.easeOut(duration: 0.25), value: value)
            ForEach(Array(GaugeScale.labels.enumerated()), id: \.offset) { i, label in
                let a = (start + sweep * Double(i) / Double(GaugeScale.labels.count - 1)) * .pi / 180
                Text(label).font(.caption2).foregroundStyle(.secondary)
                    .position(x: 130 + CGFloat(cos(a)) * 84, y: 130 + CGFloat(sin(a)) * 84)
            }
            VStack(spacing: 2) {
                Text(value.map(Self.format) ?? "–").font(.system(size: 52, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(phase).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(width: 260, height: 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(Self.format($0)) megabits per second, \(phase)" } ?? "No speed measured")
    }

    private func arc(_ fraction: Double) -> Path {
        Path { p in
            p.addArc(center: CGPoint(x: 130, y: 130), radius: 100, startAngle: .degrees(start),
                     endAngle: .degrees(start + sweep * max(0.0001, min(1, fraction))), clockwise: false)
        }
    }

    static func format(_ v: Double) -> String { v >= 100 ? String(Int(v.rounded())) : String(format: "%.1f", v) }
}
