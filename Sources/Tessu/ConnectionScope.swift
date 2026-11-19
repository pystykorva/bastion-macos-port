import Foundation
import TessuCore

/// Where a connection's far end sits. Used to hide local noise by default and to count what really
/// leaves the building.
enum ConnectionScope {
    case none, loopback, lan, multicast, internet

    static func of(_ ip: String) -> ConnectionScope {
        let s = ip.lowercased()
        if s.isEmpty || s == "*" || s == "0.0.0.0" || s == "::" { return .none }
        if s.hasPrefix("127.") || s == "::1" || s.hasPrefix("::ffff:127.") { return .loopback }
        let v4 = s.hasPrefix("::ffff:") ? String(s.dropFirst(7)) : s
        let p = v4.split(separator: ".").compactMap { Int($0) }
        if p.count == 4 {
            let (a, b) = (p[0], p[1])
            if a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 169 && b == 254) || (a == 100 && (64...127).contains(b)) { return .lan }
            if (224...239).contains(a) { return .multicast }
            return .internet
        }
        if s.hasPrefix("fe80") || s.hasPrefix("fc") || s.hasPrefix("fd") { return .lan }
        if s.hasPrefix("ff") { return .multicast }
        return .internet
    }
}

/// Well-known destination ports, so "443" reads as "HTTPS".
enum PortNames {
    static let names: [Int: String] = [
        20: "FTP data", 21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP", 53: "DNS", 67: "DHCP", 80: "HTTP", 110: "POP3",
        123: "NTP", 143: "IMAP", 443: "HTTPS", 465: "SMTPS", 587: "Mail submit", 853: "DNS over TLS", 993: "IMAPS",
        995: "POP3S", 1900: "SSDP", 3389: "Remote Desktop", 3478: "STUN", 5222: "XMPP", 5228: "Google push", 5353: "mDNS",
        5223: "Apple push", 7547: "TR-069", 8080: "HTTP alt", 8443: "HTTPS alt",
    ]
}

/// Connections of one program, for the grouped list.
struct ConnectionGroup: Identifiable {
    var id: String
    var name: String
    var pids: [Int]
    var items: [Connection]
    var internetCount: Int { items.filter { ConnectionScope.of($0.remoteIp) == .internet }.count }

    static let friendly: [String: String] = [
        "chrome": "Google Chrome", "google chrome": "Google Chrome", "google chrome helper": "Google Chrome", "msedge": "Microsoft Edge",
        "firefox": "Firefox", "brave": "Brave", "arc": "Arc", "safari": "Safari", "com.apple.webkit.networking": "Safari networking",
        "claude": "Claude", "chatgpt": "ChatGPT", "code": "Visual Studio Code", "code helper": "Visual Studio Code", "cursor": "Cursor",
        "telegram": "Telegram", "discord": "Discord", "spotify": "Spotify", "slack": "Slack", "zoom.us": "Zoom", "zoom": "Zoom",
        "mdnsresponder": "Bonjour (mDNSResponder)", "apsd": "Apple Push", "rapportd": "Apple Continuity", "cloudd": "iCloud",
        "identityservicesd": "Apple ID services", "node": "Node.js", "python": "Python", "ssh": "OpenSSH", "tessu": "Tessu",
    ]

    static func displayName(_ process: String?) -> String {
        guard let p = process, !p.isEmpty else { return "Unknown program" }
        return friendly[p.lowercased()] ?? p
    }

    static func group(_ list: [Connection]) -> [ConnectionGroup] {
        let by = Dictionary(grouping: list) { ($0.process?.isEmpty == false ? $0.process! : "?").lowercased() }
        return by.map { key, items in
            ConnectionGroup(id: key, name: displayName(items.first?.process), pids: Array(Set(items.map(\.pid))).sorted(), items: items)
        }
        // The programs talking to the most outside hosts come first.
        .sorted { ($0.internetCount, $0.items.count) > ($1.internetCount, $1.items.count) }
    }
}

enum DeviceFilter: String, CaseIterable, Identifiable {
    case all, named, unknown, random
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .named: return "Named"
        case .unknown: return "Unknown vendor"
        case .random: return "Randomized MAC"
        }
    }

    func apply(_ list: [Device]) -> [Device] {
        switch self {
        case .all: return list
        case .named: return list.filter { $0.hostname != nil }
        case .unknown: return list.filter { $0.vendor == nil }
        case .random: return list.filter(\.randomizedMac)
        }
    }
}
