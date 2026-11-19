import Foundation

public enum Overview {
    /// The public IP, from api.ipify.org (one of the few requests Tessu makes off the machine).
    /// One retry: the first request after a quiet period can stall on DNS or TLS setup.
    public static func publicIp() async -> (ip: String?, error: String?) {
        guard let url = URL(string: "https://api.ipify.org?format=json") else { return (nil, "bad URL") }
        var lastError = "unknown error"
        for _ in 0..<2 {
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return (nil, "Public IP lookup returned HTTP \(http.statusCode)")
                }
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return (obj?["ip"] as? String, nil)
            } catch {
                lastError = errMsg(error)
            }
        }
        return (nil, "Public IP lookup failed (offline or blocked): \(lastError)")
    }

    public static func overview() async -> NetworkOverview {
        async let routeTask = SystemInfo.defaultRoute()
        async let pubTask = publicIp()
        let (route, pub) = await (routeTask, pubTask)
        var errors = route.errors
        if let e = pub.error { errors.append(e) }

        var gatewayMac: String?
        if let gw = route.gateway {
            let arp = await Arp.read()
            errors.append(contentsOf: arp.errors)
            gatewayMac = arp.entries.first(where: { $0.ip == gw })?.mac
            if gatewayMac == nil && !route.localNetworkBlocked { errors.append("Gateway \(gw) is not in the ARP table yet, so its MAC address is unknown.") }
        }
        return NetworkOverview(
            hostname: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            local: .init(ip: route.ip ?? "", iface: route.iface ?? "", mac: route.mac ?? "",
                         macRandomized: route.mac.flatMap { NetUtil.isRandomizedMac($0) }),
            gateway: .init(ip: route.gateway, mac: gatewayMac, vendor: Vendors.vendor(for: gatewayMac)),
            publicIp: pub.ip,
            errors: errors)
    }

    // MARK: Wi-Fi adapter MAC (for the MAC privacy check)

    public struct WifiAdapter: Sendable {
        public var connected: Bool
        public var iface: String?
        public var mac: String?
        public var randomized: Bool?
        /// macOS hid the real MAC (Local Network access not granted).
        public var blocked = false
        public var errors: [String]
    }

    public static func wifiAdapter() async -> WifiAdapter {
        guard let dev = await SystemInfo.wifiDeviceName() else {
            return WifiAdapter(connected: false, iface: nil, mac: nil, randomized: nil, blocked: false, errors: [])
        }
        let ifc = await Exec.run("/sbin/ifconfig", [dev], timeout: 4)
        let raw = Rx.first("\\bether\\s+([0-9a-f:]+)", in: ifc.stdout, options: .caseInsensitive).flatMap { NetUtil.normalizeMac($0[1]) }
        let active = Rx.test("status:\\s*active", ifc.stdout, options: .caseInsensitive)
        let blocked = NetUtil.isRedactedMac(raw)
        let mac = blocked ? nil : raw
        return WifiAdapter(connected: active, iface: dev, mac: mac, randomized: mac.flatMap { NetUtil.isRandomizedMac($0) },
                           blocked: blocked, errors: [])
    }
}
