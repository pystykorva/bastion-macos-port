import Foundation
import CoreWLAN

extension Wifi {
    /// Neighbouring networks from a CoreWLAN scan. Blocks for a few seconds, so it runs off the
    /// cooperative pool. Names and BSSIDs are empty without Location access; channels and signal are real.
    static func scanNeighbours() async -> (networks: [WifiNetwork], redacted: Int, error: String?) {
        await blocking {
            guard let iface = CWWiFiClient.shared().interface() else {
                return ([], 0, "No Wi-Fi adapter was found on this Mac.")
            }
            let found: Set<CWNetwork>
            do { found = try iface.scanForNetworks(withSSID: nil) } catch {
                return ([], 0, "macOS could not scan for nearby networks: \(error.localizedDescription)")
            }
            var out: [WifiNetwork] = []
            var redacted = 0
            for n in found {
                guard let ch = n.wlanChannel else { continue }
                let band = Wifi.band(ch.channelBand) ?? WifiLogic.band(fromChannel: ch.channelNumber)
                guard let b = band else { continue }
                let name = Wifi.visible(n.ssid)
                if name == nil { redacted += 1 }
                let rssi = n.rssiValue == 0 ? nil : n.rssiValue
                out.append(WifiNetwork(ssid: name ?? "", bssid: NetUtil.normalizeMac(n.bssid), channel: ch.channelNumber,
                                       band: b, signalPct: WifiLogic.rssiToPct(rssi), rssi: rssi, widthMHz: Wifi.width(ch.channelWidth)))
            }
            return (out, redacted, nil)
        }
    }

    public static func survey() async -> WifiSurvey {
        async let infoTask = info()
        async let scanTask = scanNeighbours()
        let (link, scan) = await (infoTask, scanTask)

        var out = WifiSurvey()
        out.currentChannel = link.channel
        out.currentBand = link.band
        if let e = scan.error {
            out.errors = [e]
            return out
        }
        out.supported = true
        var networks = scan.networks
        // The connected network is part of the picture too (a scan can omit it).
        if let ch = link.channel, let b = link.band,
           !networks.contains(where: { $0.channel == ch && $0.bssid != nil && $0.bssid == link.bssid }) {
            networks.append(WifiNetwork(ssid: link.ssid ?? "", bssid: link.bssid, channel: ch, band: b,
                                        signalPct: link.signalPct, rssi: link.rssi, widthMHz: link.widthMHz, own: true))
        }
        networks = WifiLogic.dedupe(networks)
        WifiLogic.markOwn(&networks, info: link)

        var errors: [String] = []
        if scan.redacted > 0 && scan.redacted == scan.networks.count { errors.append(locationHint) }
        if scan.networks.isEmpty { errors.append("macOS did not report any nearby networks. Try again in a moment.") }
        if link.ssid == nil && link.supported && link.channel == nil {
            errors.append("Not connected to Wi-Fi, so there is no current channel to compare.")
        }
        out.recommendation = WifiLogic.recommend(networks, band: link.band, channel: link.channel, width: link.widthMHz)
        networks.sort { ($0.signalPct ?? 0) > ($1.signalPct ?? 0) }
        out.networks = networks
        out.congestion = WifiLogic.buildCongestion(networks, currentBand: link.band, currentChannel: link.channel)
        out.errors = errors
        return out
    }
}
