import Foundation

extension WifiLogic {
    /// Advice on which channel to move to, or nil when the current one is fine (or the band is 6 GHz,
    /// which is rarely crowded).
    public static func recommend(_ networks: [WifiNetwork], band: WifiBand?, channel: Int?, width: Int?) -> ChannelRecommendation? {
        guard let band = band, let channel = channel else { return nil }
        guard band == .ghz24 || band == .ghz5 else { return nil }
        let now = neighboursOn(networks, band: band, channel: channel, width: width)

        func score(_ c: Int) -> (channel: Int, count: Int, weight: Int) {
            let n = neighboursOn(networks, band: band, channel: c, width: width)
            return (c, n.count, n.weight)
        }
        func better(_ a: (channel: Int, count: Int, weight: Int), _ b: (channel: Int, count: Int, weight: Int)) -> Bool {
            a.count != b.count ? a.count < b.count : a.weight < b.weight
        }
        func best(_ list: [Int]) -> (channel: Int, count: Int, weight: Int)? {
            list.map(score).sorted(by: better).first // stable: earlier candidates win ties
        }

        var pick: (channel: Int, count: Int, weight: Int)?
        var dfs = false
        if band == .ghz24 {
            pick = best(candidates24)
        } else {
            pick = best(nonDfs5)
            // DFS only when it is clearly better: at least two fewer neighbours than the best non-DFS option.
            if let d = best(dfs5), let p = pick, d.count <= p.count - 2 {
                pick = d
                dfs = true
            }
        }
        guard let target = pick, target.channel != channel, target.count < now.count else { return nil }
        // Skip moves inside the same wide block: they change nothing for a wide channel.
        if band == .ghz5, let w = width, w > 20, occupied5(channel, width: w).contains(target.channel) { return nil }

        let label = band == .ghz24 ? "2.4 GHz" : "5 GHz"
        func nets(_ n: Int) -> String { n == 1 ? "1 network" : "\(n) networks" }
        var reason = "On \(label), channel \(channel) currently shares airtime with \(nets(now.count)) nearby; " +
            "channel \(target.channel) overlaps with \(nets(target.count)). " +
            "Fewer overlapping networks means less waiting to transmit and more stable speed. " +
            "Change the channel in your router's Wi-Fi settings (set it manually instead of Auto)."
        if band == .ghz24 { reason += " On 2.4 GHz only channels 1, 6 and 11 avoid partial overlap." }
        if dfs {
            reason += " This is a DFS channel: the router must listen for radar first, so Wi-Fi may take about a minute to come up and can briefly move channels if radar is detected."
        }
        if width == nil { reason += " Counts assume 20 MHz channels because channel width is not reported on this computer." }
        return ChannelRecommendation(channel: target.channel, band: band, reason: reason,
                                     neighboursNow: now.count, neighboursThere: target.count)
    }
}
