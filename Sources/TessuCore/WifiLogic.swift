import Foundation

/// Pure Wi-Fi analysis: channel overlap, congestion, recommendation, own-router detection.
/// Ported 1:1 from engine/wifi.js so the advice stays identical; no OS calls in here.
public enum WifiLogic {
    // MARK: helpers

    public static func band(fromChannel channel: Int?) -> WifiBand? {
        guard let c = channel else { return nil }
        if (1...14).contains(c) { return .ghz24 }
        if (32...177).contains(c) { return .ghz5 }
        return nil
    }

    public static func isNomap(_ ssid: String?) -> Bool? {
        guard let s = ssid?.lowercased() else { return nil }
        return s.hasSuffix("_nomap") || s.contains("_optout")
    }

    public static func rssiToPct(_ rssi: Int?) -> Int? {
        guard let r = rssi else { return nil }
        return max(0, min(100, (r + 100) * 2))
    }

    // MARK: channel geometry

    static let blockStarts5: [Int: [Int]] = [
        40: [36, 44, 52, 60, 100, 108, 116, 124, 132, 140, 149, 157, 165, 173],
        80: [36, 52, 100, 116, 132, 149, 165],
        160: [36, 100, 149],
    ]
    static let candidates24 = [1, 6, 11]
    static let nonDfs5 = [36, 40, 44, 48, 149, 153, 157, 161, 165]
    static let dfs5 = [52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144]

    /// 20 MHz channels a 5 GHz transmission occupies, given its primary channel and width.
    public static func occupied5(_ channel: Int, width: Int?) -> [Int] {
        guard let w = width, let starts = blockStarts5[w] else { return [channel] }
        let span = w / 5 - 4 // 40 -> 4, 80 -> 12, 160 -> 28
        guard let start = starts.first(where: { channel >= $0 && channel <= $0 + span }) else { return [channel] }
        return Array(stride(from: start, through: start + span, by: 4))
    }

    static func overlaps(_ band: WifiBand, _ a: Int, _ aWidth: Int?, _ b: Int, _ bWidth: Int?) -> Bool {
        switch band {
        case .ghz24: return abs(a - b) <= 4
        case .ghz5: return !Set(occupied5(a, width: aWidth)).isDisjoint(with: occupied5(b, width: bWidth))
        case .ghz6: return a == b
        }
    }

    static func neighboursOn(_ networks: [WifiNetwork], band: WifiBand, channel: Int, width: Int?) -> (count: Int, weight: Int) {
        var count = 0, weight = 0
        for n in networks where n.band == band && !n.own {
            guard overlaps(band, channel, width, n.channel, n.widthMHz) else { continue }
            count += 1
            weight += n.signalPct ?? 50
        }
        return (count, weight)
    }
}
