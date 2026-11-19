import Foundation

public struct DefaultRoute: Sendable {
    public var gateway: String?
    public var iface: String?
    public var ip: String?
    public var prefix: Int?
    public var mac: String?
    /// true when the default interface is the Wi-Fi port; nil when unknown.
    public var isWifi: Bool?
    /// macOS is hiding local-network data from this app (Local Network permission not granted).
    public var localNetworkBlocked = false
    public var errors: [String] = []

    public init(gateway: String? = nil, iface: String? = nil, ip: String? = nil, prefix: Int? = nil,
                mac: String? = nil, isWifi: Bool? = nil, localNetworkBlocked: Bool = false, errors: [String] = []) {
        self.gateway = gateway; self.iface = iface; self.ip = ip; self.prefix = prefix
        self.mac = mac; self.isWifi = isWifi; self.localNetworkBlocked = localNetworkBlocked; self.errors = errors
    }
}

public enum SystemInfo {
    private static let routeCache = Cache<DefaultRoute>(ttl: 10)

    /// The default route, cached for 10 s (every scan step asks for it).
    public static func defaultRoute(force: Bool = false) async -> DefaultRoute {
        if !force, let hit = routeCache.value { return hit }
        var errors: [String] = []
        var r = await macRoute(&errors)
        if r == nil {
            // Last resort: any private IPv4 interface, gateway unknown.
            if let n = Interfaces.ipv4().first(where: { NetUtil.isPrivateIPv4($0.ip) }) {
                r = DefaultRoute(gateway: nil, iface: n.name, ip: n.ip, prefix: n.prefix, mac: n.mac, isWifi: nil,
                                 localNetworkBlocked: n.macRedacted)
            }
            errors.append("No default route found: this computer may be offline.")
        }
        var value = r ?? DefaultRoute()
        if value.localNetworkBlocked { errors.append(LocalNetwork.blockedMessage) }
        value.errors = errors
        if let gw = value.gateway, let ip = value.ip, let prefix = value.prefix,
           !NetUtil.sameSubnet(gw, ip, prefix: prefix) {
            value.errors.append("Gateway \(gw) is outside the local subnet \(ip)/\(prefix) (VPN or unusual setup).")
        }
        routeCache.set(value)
        return value
    }

    static func parseRouteGet(_ text: String) -> (gateway: String?, iface: String?) {
        let gw = Rx.first("gateway:\\s*(\\S+)", in: text)?[1]
        let ifc = Rx.first("interface:\\s*(\\S+)", in: text)?[1]
        return (NetUtil.isIPv4(gw) ? gw : nil, ifc)
    }

    private static func macRoute(_ errors: inout [String]) async -> DefaultRoute? {
        let res = await Exec.run("/sbin/route", ["-n", "get", "default"])
        if let e = res.error { errors.append(e) }
        let parsed = parseRouteGet(res.stdout)
        var gateway = parsed.gateway
        let ifaces = Interfaces.ipv4()
        var n = parsed.iface.flatMap { name in ifaces.first { $0.name == name } }
        // A VPN (utun) can own the default route; fall back to the first physical interface.
        if gateway == nil || n == nil {
            if let alt = ifaces.first(where: { Rx.test("^en\\d+$", $0.name) }) {
                n = alt
                if gateway == nil {
                    let r2 = await Exec.run("/usr/sbin/ipconfig", ["getoption", alt.name, "router"])
                    let t = r2.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    if NetUtil.isIPv4(t) { gateway = t }
                }
            }
        }
        if n == nil && gateway == nil { return nil }
        let wifiDevice = await wifiDeviceName()
        let isWifi: Bool? = (n?.name).flatMap { name in wifiDevice.map { $0 == name } }
        return DefaultRoute(gateway: gateway, iface: n?.name ?? parsed.iface, ip: n?.ip, prefix: n?.prefix ?? 24,
                            mac: n?.mac, isWifi: isWifi, localNetworkBlocked: n?.macRedacted ?? false)
    }

    /// The BSD device of the Wi-Fi port (usually en0), from `networksetup -listallhardwareports`.
    static func wifiDeviceName() async -> String? {
        let hw = await Exec.run("/usr/sbin/networksetup", ["-listallhardwareports"], timeout: 5)
        return Rx.first("Hardware Port:\\s*(?:Wi-Fi|AirPort)\\s*\\r?\\nDevice:\\s*(\\S+)", in: hw.stdout, options: .caseInsensitive)?[1]
    }
}
