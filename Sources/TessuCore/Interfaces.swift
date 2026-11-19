import Foundation
import Darwin

/// One IPv4 interface as the system reports it.
struct IfaceAddress: Sendable {
    var name: String
    var ip: String
    var prefix: Int
    var mac: String?
    /// The system hid the real MAC (no Local Network access).
    var macRedacted = false
}

/// A single value with a time-to-live.
final class Cache<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (at: Date, value: T)?
    private let ttl: TimeInterval
    init(ttl: TimeInterval) { self.ttl = ttl }

    var value: T? {
        lock.lock(); defer { lock.unlock() }
        guard let s = stored, Date().timeIntervalSince(s.at) < ttl else { return nil }
        return s.value
    }

    func set(_ v: T) {
        lock.lock(); stored = (Date(), v); lock.unlock()
    }

    func clear() {
        lock.lock(); stored = nil; lock.unlock()
    }
}

enum Interfaces {
    private static func ipString(_ sin: sockaddr_in) -> String {
        var a = sin.sin_addr
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &a, &buf, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buf)
    }

    /// MAC per interface name, from the link-layer entries of getifaddrs.
    private static func linkAddresses(_ first: UnsafeMutablePointer<ifaddrs>) -> [String: String] {
        var macs: [String: String] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cursor {
            let ifa = p.pointee
            cursor = ifa.ifa_next
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: ifa.ifa_name)
            addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dl in
                let alen = Int(dl.pointee.sdl_alen)
                let nlen = Int(dl.pointee.sdl_nlen)
                guard alen == 6 else { return }
                let raw = UnsafeRawPointer(dl).advanced(by: MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)!)
                let bytes = (0..<alen).map { raw.load(fromByteOffset: nlen + $0, as: UInt8.self) }
                macs[name] = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
            }
        }
        return macs
    }

    /// IPv4 interfaces that are up and not loopback, with their MACs.
    static func ipv4() -> [IfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        let macs = linkAddresses(first)

        var out: [IfaceAddress] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cursor {
            let ifa = p.pointee
            cursor = ifa.ifa_next
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ipString($0.pointee) }
            var prefix = 24
            if let mask = ifa.ifa_netmask {
                let m = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ipString($0.pointee) }
                prefix = NetUtil.maskToPrefix(m) ?? 24
            }
            let mac = NetUtil.normalizeMac(macs[name])
            let redacted = NetUtil.isRedactedMac(mac)
            out.append(IfaceAddress(name: name, ip: ip, prefix: prefix, mac: redacted ? nil : mac, macRedacted: redacted))
        }
        return out
    }
}
