import Foundation

/// MAC / IPv4 helpers. Direct ports of the helpers in the original engine/util.js.
public enum NetUtil {
    /// 'aa:bb:cc:dd:ee:ff' or nil. Accepts '-', ':' or '.' separators and unpadded octets (macOS arp).
    public static func normalizeMac(_ mac: String?) -> String? {
        guard let mac = mac else { return nil }
        let s = mac.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        var parts: [String]
        let flat = s.replacingOccurrences(of: ".", with: "")
        if s.count == 12, s.allSatisfy({ $0.isHexDigit }) {
            parts = pairs(s)
        } else if Rx.test("^[0-9a-f]{4}\\.[0-9a-f]{4}\\.[0-9a-f]{4}$", s) {
            parts = pairs(flat)
        } else {
            parts = s.split(omittingEmptySubsequences: false, whereSeparator: { $0 == ":" || $0 == "-" }).map(String.init)
        }
        guard parts.count == 6, parts.allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy { $0.isHexDigit } }) else { return nil }
        let out = parts.map { $0.count == 1 ? "0" + $0 : $0 }.joined(separator: ":")
        return out == "00:00:00:00:00:00" ? nil : out
    }

    private static func pairs(_ s: String) -> [String] {
        stride(from: 0, to: s.count, by: 2).map { i in
            let a = s.index(s.startIndex, offsetBy: i)
            return String(s[a..<s.index(a, offsetBy: 2)])
        }
    }

    /// Locally-administered bit set: not a burned-in vendor address (phones and laptops use these for privacy).
    public static func isRandomizedMac(_ mac: String?) -> Bool? {
        guard let m = normalizeMac(mac), let first = UInt8(m.prefix(2), radix: 16) else { return nil }
        if first & 0x01 != 0 { return false }
        return first & 0x02 != 0
    }

    /// macOS shows 02:00:00:00:00:00 instead of the real hardware address to apps that were not granted
    /// Local Network access. It looks like a randomized address, so it must never be judged as one.
    public static func isRedactedMac(_ mac: String?) -> Bool {
        normalizeMac(mac) == "02:00:00:00:00:00"
    }

    public static func isMulticastMac(_ mac: String?) -> Bool {
        guard let m = normalizeMac(mac), let first = UInt8(m.prefix(2), radix: 16) else { return false }
        return m == "ff:ff:ff:ff:ff:ff" || first & 0x01 == 1
    }

    public static func isIPv4(_ ip: String?) -> Bool {
        guard let ip = ip else { return false }
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.count <= 3 && $0.allSatisfy(\.isASCIIDigit) && (Int($0) ?? 999) <= 255 }
    }

    public static func ipToInt(_ ip: String) -> UInt32 {
        ip.split(separator: ".").reduce(UInt32(0)) { ($0 << 8) | (UInt32($1) ?? 0) }
    }

    public static func intToIp(_ n: UInt32) -> String {
        "\(n >> 24).\((n >> 16) & 255).\((n >> 8) & 255).\(n & 255)"
    }

    public static func prefixToMask(_ prefix: Int) -> UInt32 {
        prefix <= 0 ? 0 : (prefix >= 32 ? UInt32.max : UInt32.max << UInt32(32 - prefix))
    }

    public static func maskToPrefix(_ mask: String) -> Int? {
        guard isIPv4(mask) else { return nil }
        var n = ipToInt(mask)
        var bits = 0
        while n & 0x8000_0000 != 0 { bits += 1; n <<= 1 }
        return bits
    }

    public static func sameSubnet(_ a: String?, _ b: String?, prefix: Int?) -> Bool {
        guard let a = a, let b = b, let prefix = prefix, isIPv4(a), isIPv4(b) else { return false }
        let m = prefixToMask(prefix)
        return ipToInt(a) & m == ipToInt(b) & m
    }

    /// RFC 1918 + link-local: addresses that only exist inside a local network.
    public static func isPrivateIPv4(_ ip: String?) -> Bool {
        guard isIPv4(ip), let ip = ip else { return false }
        let p = ip.split(separator: ".").compactMap { Int($0) }
        let (a, b) = (p[0], p[1])
        return a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 169 && b == 254)
    }

    public static func isLoopback(_ ip: String?) -> Bool {
        guard let ip = ip, !ip.isEmpty else { return false }
        var s = ip.lowercased()
        if s.hasPrefix("[") { s.removeFirst() }
        if s.hasSuffix("]") { s.removeLast() }
        return s.hasPrefix("127.") || s == "::1" || s == "::ffff:127.0.0.1" || s == "localhost"
    }

    public static func isMulticastIPv4(_ ip: String?) -> Bool {
        guard isIPv4(ip), let first = ip?.split(separator: ".").first.flatMap({ Int($0) }) else { return false }
        return (224...239).contains(first)
    }
}

extension Character {
    var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
