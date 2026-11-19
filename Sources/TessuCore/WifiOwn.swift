import Foundation

extension WifiLogic {
    /// True when two BSSIDs look like siblings on one router. Routers give their other-band radios the
    /// next few addresses after the base, and derive guest/hidden/backhaul BSSIDs by setting the
    /// locally-administered (LA) bit and flipping a few more bits (8c:90:2d:37:09:7e and
    /// 8e:90:2d:77:09:7c). Neighbours of the same model bought in one batch have near-sequential
    /// universal addresses too, so the rule is narrow:
    ///  - both universal: same OUI and octets 4-5, last octet in the same block of 8;
    ///  - LA bit set on either: same first three octets ignoring the LA bit, at most 3 differing
    ///    bits in octets 4-6.
    public static func siblingBssid(_ a: String?, _ b: String?) -> Bool {
        guard let a = a, let b = b, a != b else { return false }
        let pa = a.split(separator: ":").compactMap { Int($0, radix: 16) }
        let pb = b.split(separator: ":").compactMap { Int($0, radix: 16) }
        guard pa.count == 6, pb.count == 6 else { return false }
        guard (pa[0] & ~0x02) == (pb[0] & ~0x02), pa[1] == pb[1], pa[2] == pb[2] else { return false }
        if (pa[0] | pb[0]) & 0x02 == 0 {
            return pa[3] == pb[3] && pa[4] == pb[4] && (pa[5] & 0xf8) == (pb[5] & 0xf8)
        }
        var bits = 0
        for i in 3..<6 { bits += (pa[i] ^ pb[i]).nonzeroBitCount }
        return bits <= 3
    }

    /// Marks the user's own access points (connected BSSID, same SSID, or sibling BSSIDs of the same
    /// router) so they are not counted as competing neighbours.
    public static func markOwn(_ networks: inout [WifiNetwork], info: WifiInfo) {
        for i in networks.indices where !networks[i].own {
            let n = networks[i]
            if let b = info.bssid, n.bssid == b { networks[i].own = true }
            else if let s = info.ssid, !n.ssid.isEmpty, n.ssid == s { networks[i].own = true }
            else if let b = info.bssid, siblingBssid(n.bssid, b) { networks[i].own = true }
        }
    }

    public static func buildCongestion(_ networks: [WifiNetwork], currentBand: WifiBand?, currentChannel: Int?) -> [CongestionEntry] {
        var out: [CongestionEntry] = []
        var seen = Set<String>()
        func add(_ band: WifiBand, _ channel: Int) {
            guard seen.insert("\(band.rawValue):\(channel)").inserted else { return }
            out.append(CongestionEntry(channel: channel, band: band, count: neighboursOn(networks, band: band, channel: channel, width: nil).count))
        }
        var bands = Set(networks.map(\.band))
        if let b = currentBand { bands.insert(b) }
        if bands.contains(.ghz24) { candidates24.forEach { add(.ghz24, $0) } }
        if bands.contains(.ghz5) { nonDfs5.forEach { add(.ghz5, $0) } }
        for n in networks { add(n.band, n.channel) }
        if let c = currentChannel, let b = currentBand { add(b, c) }
        return out.sorted { $0.band == $1.band ? $0.channel < $1.channel : $0.band < $1.band }
    }

    /// One entry per access point: the strongest reading wins, "own" sticks.
    public static func dedupe(_ networks: [WifiNetwork]) -> [WifiNetwork] {
        var byKey: [String: WifiNetwork] = [:]
        var order: [String] = []
        for n in networks {
            let key = n.bssid ?? "\(n.ssid)|\(n.band.rawValue)|\(n.channel)|\(n.own ? "own" : String(n.rssi ?? 0))"
            if let prev = byKey[key] {
                if (n.signalPct ?? 0) > (prev.signalPct ?? 0) || n.own {
                    var merged = n
                    merged.own = n.own || prev.own
                    byKey[key] = merged
                }
            } else {
                byKey[key] = n
                order.append(key)
            }
        }
        return order.compactMap { byKey[$0] }
    }
}
