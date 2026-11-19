import SwiftUI
import Charts
import TessuCore

/// Which Wi-Fi channels are busy: every network Tessu heard, as a bar at its channel with its signal
/// strength as the height. Your own router is highlighted and the recommended channel is marked, so the
/// advice can be read straight off the chart. A plain Swift Charts bar chart: no decoration.
struct ChannelChart: View {
    var survey: WifiSurvey
    var band: WifiBand
    var currentChannel: Int?

    private var networks: [WifiNetwork] { survey.networks.filter { $0.band == band } }

    /// One bar per heard network, stacked per channel, own router coloured differently.
    var body: some View {
        let recommended = survey.recommendation.flatMap { $0.band == band ? $0.channel : nil }
        Chart {
            ForEach(networks) { n in
                BarMark(x: .value("Channel", String(n.channel)), y: .value("Signal", n.signalPct ?? 0), width: .ratio(0.6), stacking: .unstacked)
                    .foregroundStyle(by: .value("Network", n.own ? "Your router" : "Neighbours"))
                    .opacity(n.own ? 1 : 0.55)
            }
            if let c = recommended {
                RuleMark(x: .value("Channel", String(c)))
                    .foregroundStyle(Theme.lavender)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .annotation(position: .top, alignment: .center) {
                        Label("Try \(c)", systemImage: "arrow.down.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.lavender)
                    }
            }
        }
        .chartForegroundStyleScale(["Your router": Color(Theme.color(.ok)), "Neighbours": Color.secondary])
        .chartXScale(domain: channels(including: recommended))
        .chartYScale(domain: 0...100)
        .chartYAxisLabel("Signal %")
        .chartXAxisLabel("Channel")
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 220)
        .clipped()
        .accessibilityLabel(accessibilitySummary)
    }

    /// Axis domain: every channel that has a network, plus the router's own and the recommended one.
    private func channels(including extra: Int?) -> [String] {
        var set = Set(networks.map(\.channel))
        if let c = currentChannel, survey.currentBand == band { set.insert(c) }
        if let e = extra { set.insert(e) }
        if band == .ghz24 { [1, 6, 11].forEach { set.insert($0) } }
        return set.sorted().map(String.init)
    }

    private var accessibilitySummary: String {
        let others = networks.filter { !$0.own }.count
        let rec = survey.recommendation.flatMap { $0.band == band ? " Recommended channel \($0.channel)." : nil } ?? ""
        return "\(band.label) channels: \(others) neighbouring networks.\(rec)"
    }
}

/// The same data as a table, for people who prefer numbers and for VoiceOver: per channel, how many
/// neighbours overlap it.
struct CongestionTable: View {
    var survey: WifiSurvey
    var band: WifiBand

    var body: some View {
        let rows = survey.congestion.filter { $0.band == band }
        VStack(spacing: 0) {
            ForEach(rows, id: \.channel) { row in
                HStack {
                    Text("Channel \(row.channel)").font(.callout.monospacedDigit())
                    if row.channel == survey.currentChannel && survey.currentBand == band { Text("yours").font(.caption).foregroundStyle(Theme.color(.ok)) }
                    if survey.recommendation?.channel == row.channel && survey.recommendation?.band == band {
                        Text("recommended").font(.caption).foregroundStyle(Theme.lavender)
                    }
                    Spacer()
                    Text("\(row.count) overlapping").font(.callout).foregroundStyle(row.count == 0 ? Theme.color(.ok) : .secondary)
                }
                .padding(.vertical, 5)
                Divider()
            }
        }
    }
}
