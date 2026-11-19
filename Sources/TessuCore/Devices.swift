import Foundation
import Darwin

public enum Devices {
    /// Name for an address through the system resolver, which also reaches mDNS / Bonjour.
    static func reverseName(_ ip: String) -> String? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, ip, &addr.sin_addr)
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard rc == 0 else { return nil }
        var name = String(cString: host)
        if name.hasSuffix(".") { name.removeLast() }
        return name.isEmpty || name == ip ? nil : name
    }

    static func reverseNames(_ ips: [String]) async -> [String: String] {
        let found = await mapLimit(ips, limit: 16) { ip -> (String, String?) in
            let name: String? = await withTimeout(2.0, fallback: nil) { await blocking { reverseName(ip) } }
            return (ip, name)
        }
        var out: [String: String] = [:]
        for (ip, name) in found { if let name = name { out[ip] = name } }
        return out
    }

    static var thisHostName: String { Host.current().localizedName ?? ProcessInfo.processInfo.hostName }

    /// Devices this computer can see on the local network (ARP neighbours after a warm-up sweep).
    public static func discover(sweep: Bool = true) async -> DeviceList {
        var errors: [String] = []
        let route = await SystemInfo.defaultRoute()
        errors.append(contentsOf: route.errors)
        if sweep, let ip = route.ip { await Arp.sweepSubnet(ip: ip, prefix: route.prefix) }
        let arp = await Arp.read()
        errors.append(contentsOf: arp.errors)

        // Keep only the neighbours on the interface that carries the default route.
        var entries = arp.entries
        if let iface = route.iface {
            let onRoute = entries.filter { $0.iface == iface }
            if !onRoute.isEmpty { entries = onRoute }
        }

        var seen = Set<String>()
        var list: [Device] = []
        for e in entries where seen.insert(e.ip).inserted {
            list.append(Device(
                ip: e.ip, mac: e.mac, vendor: Vendors.vendor(for: e.mac),
                randomizedMac: NetUtil.isRandomizedMac(e.mac) ?? false,
                isGateway: e.ip == route.gateway,
                // macOS lists this computer's own address as a permanent ARP entry.
                isThisComputer: e.ip == route.ip,
                hostname: e.ip == route.ip ? thisHostName : nil))
        }
        if let ip = route.ip, !seen.contains(ip) {
            list.append(Device(
                ip: ip, mac: route.mac ?? "", vendor: Vendors.vendor(for: route.mac),
                randomizedMac: NetUtil.isRandomizedMac(route.mac) ?? false,
                isGateway: false, isThisComputer: true, hostname: thisHostName))
        }

        let others = list.filter { !$0.isThisComputer && NetUtil.isIPv4($0.ip) }.map(\.ip)
        let names = await reverseNames(others)
        for i in list.indices where list[i].hostname == nil { list[i].hostname = names[list[i].ip] }

        list.sort {
            if $0.isGateway != $1.isGateway { return $0.isGateway }
            if $0.isThisComputer != $1.isThisComputer { return $0.isThisComputer }
            return NetUtil.ipToInt($0.ip) < NetUtil.ipToInt($1.ip)
        }
        return DeviceList(devices: list, errors: errors)
    }
}
