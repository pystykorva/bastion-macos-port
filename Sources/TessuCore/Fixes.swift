import Foundation

/// Opens the settings page or router admin page for a guided fix. Never changes anything itself.
public enum Fixes {
    static let settingsURLs: [FixTarget: String] = [
        .dnsSettings: "x-apple.systempreferences:com.apple.Network-Settings.extension",
        .wifiSettings: "x-apple.systempreferences:com.apple.wifi-settings-extension",
        .macPrivacy: "x-apple.systempreferences:com.apple.wifi-settings-extension",
    ]

    /// The URL a fix target opens, or nil with the reason it cannot.
    /// The router admin page is plain HTTP on a private address, which is fine on the local network.
    public static func url(for target: FixTarget) async -> (url: URL?, error: String?) {
        if target == .routerAdmin {
            let route = await SystemInfo.defaultRoute()
            guard let gw = route.gateway, NetUtil.isIPv4(gw), NetUtil.isPrivateIPv4(gw) else {
                return (nil, "The router address is unknown or not on the local network.")
            }
            return (URL(string: "http://\(gw)/"), nil)
        }
        guard let s = settingsURLs[target], let url = URL(string: s) else { return (nil, "Unknown fix target: \(target.rawValue)") }
        return (url, nil)
    }
}
