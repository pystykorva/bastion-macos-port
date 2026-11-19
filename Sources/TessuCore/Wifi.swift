import Foundation
import CoreWLAN

/// Wi-Fi link info and neighbourhood survey, read straight from CoreWLAN (no text parsing).
public enum Wifi {
    /// macOS 14.4+ hides SSIDs and BSSIDs from apps that have not been granted Location access.
    public static let locationHint =
        "macOS hides Wi-Fi network names from apps without Location access, so the name is unknown. " +
        "Allow Tessu under System Settings > Privacy & Security > Location Services. " +
        "Channel, signal and speed readings are still real."

    static func band(_ b: CWChannelBand) -> WifiBand? {
        switch b {
        case .band2GHz: return .ghz24
        case .band5GHz: return .ghz5
        case .band6GHz: return .ghz6
        default: return nil
        }
    }

    static func width(_ w: CWChannelWidth) -> Int? {
        switch w {
        case .width20MHz: return 20
        case .width40MHz: return 40
        case .width80MHz: return 80
        case .width160MHz: return 160
        default: return nil
        }
    }

    /// Same labels the scan checks match on ("WPA3", "WPA2", "WEP", "Open", "TKIP").
    static func securityLabel(_ s: CWSecurity) -> String? {
        switch s {
        case .none: return "Open"
        case .WEP, .dynamicWEP: return "WEP"
        case .wpaPersonal: return "WPA-Personal"
        case .wpaPersonalMixed: return "WPA/WPA2-Personal"
        case .wpa2Personal: return "WPA2-Personal"
        case .personal: return "WPA2/WPA3-Personal"
        case .wpa3Personal: return "WPA3-Personal"
        case .wpa3Transition: return "WPA2/WPA3-Personal"
        case .wpaEnterprise: return "WPA-Enterprise"
        case .wpaEnterpriseMixed: return "WPA/WPA2-Enterprise"
        case .wpa2Enterprise: return "WPA2-Enterprise"
        case .enterprise: return "WPA2/WPA3-Enterprise"
        case .wpa3Enterprise: return "WPA3-Enterprise"
        case .OWE, .oweTransition: return "OWE (Enhanced Open)"
        default: return nil
        }
    }

    /// An SSID the system blanked out (Location not granted) reads as empty or "<redacted>".
    static func visible(_ ssid: String?) -> String? {
        guard let s = ssid, !s.isEmpty, !s.lowercased().contains("redacted") else { return nil }
        return s
    }

    static func ssidFallback(_ iface: String) async -> String? {
        let res = await Exec.run("/usr/sbin/ipconfig", ["getsummary", iface], timeout: 4)
        guard let m = Rx.first("^\\s*SSID\\s*:\\s*(.+)$", in: res.stdout, options: .anchorsMatchLines) else { return nil }
        return visible(m[1].trimmingCharacters(in: .whitespaces))
    }

    // MARK: link info

    public static func info() async -> WifiInfo {
        var out = WifiInfo()
        guard let iface = CWWiFiClient.shared().interface() else {
            out.errors = ["No Wi-Fi adapter was found on this Mac."]
            return out
        }
        out.supported = true
        guard iface.powerOn() else {
            out.errors = ["Wi-Fi is turned off on this Mac."]
            return out
        }
        guard let channel = iface.wlanChannel() else {
            out.errors = ["This Mac is not connected to a Wi-Fi network right now."]
            return out
        }
        var ssid = visible(iface.ssid())
        if ssid == nil, let name = iface.interfaceName { ssid = await ssidFallback(name) }
        if ssid == nil { out.errors.append(locationHint) }
        let rssi = iface.rssiValue()
        let rate = iface.transmitRate()
        out.ssid = ssid
        out.bssid = NetUtil.normalizeMac(iface.bssid())
        out.band = band(channel.channelBand) ?? WifiLogic.band(fromChannel: channel.channelNumber)
        out.channel = channel.channelNumber
        out.widthMHz = width(channel.channelWidth)
        out.rssi = rssi == 0 ? nil : rssi
        out.signalPct = WifiLogic.rssiToPct(out.rssi)
        // macOS reports a single negotiated rate for both directions.
        out.rxMbps = rate > 0 ? rate : nil
        out.txMbps = rate > 0 ? rate : nil
        out.security = securityLabel(iface.security())
        out.nomap = WifiLogic.isNomap(ssid)
        return out
    }
}
