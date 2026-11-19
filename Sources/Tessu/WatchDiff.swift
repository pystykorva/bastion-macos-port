import Foundation
import TessuCore

/// A frozen picture of the network, compared with the next one to find what changed.
struct WatchSnapshot {
    var at = Date()
    /// MAC (or IP) -> display name. nil = devices were not read, so nothing can be said about them.
    var devices: [String: String]?
    var checks: [String: (status: CheckStatus, title: String)] = [:]
    var wifi: (ssid: String?, channel: Int?, signalPct: Int?)?
    var publicIp: String?
    var dns: (servers: String, provider: String?, encrypted: Bool?)?

    @MainActor
    static func capture(_ s: AppState) -> WatchSnapshot {
        var out = WatchSnapshot()
        if let list = s.devices?.devices {
            out.devices = Dictionary(list.map { ($0.mac.isEmpty ? $0.ip : $0.mac, $0.hostname ?? $0.vendor ?? $0.ip) }, uniquingKeysWith: { a, _ in a })
        }
        for c in s.scan?.checks ?? [] { out.checks[c.id] = (c.status, c.title) }
        if let w = s.wifi, w.supported { out.wifi = (w.ssid, w.channel, w.signalPct) }
        out.publicIp = s.overview?.publicIp
        if let d = s.dns { out.dns = (d.servers.joined(separator: ", "), d.provider, d.encrypted) }
        return out
    }
}

struct WatchChange: Equatable {
    enum Level: Int { case info = 0, warn = 1, risk = 2 }
    var level: Level
    var text: String
}

enum WatchDiff {
    static func changes(from a: WatchSnapshot, to b: WatchSnapshot) -> [WatchChange] {
        var out: [WatchChange] = []
        if let da = a.devices, let db = b.devices {
            for (k, name) in db where da[k] == nil { out.append(.init(level: .warn, text: "New device: \(name) (\(k))")) }
            for (k, name) in da where db[k] == nil { out.append(.init(level: .info, text: "Device no longer seen: \(name) (\(k))")) }
        }
        for (id, c) in b.checks {
            guard let before = a.checks[id], before.status != c.status else { continue }
            let level: WatchChange.Level = c.status == .risk ? .risk : c.status == .warn ? .warn : .info
            out.append(.init(level: level, text: "Check \"\(c.title)\" changed from \(before.status.rawValue) to \(c.status.rawValue)"))
        }
        if let wa = a.wifi, let wb = b.wifi {
            if wa.ssid != wb.ssid {
                out.append(.init(level: .warn, text: "Wi-Fi network changed from \(wa.ssid ?? "unknown") to \(wb.ssid ?? "unknown")"))
            } else if wa.channel != wb.channel {
                out.append(.init(level: .info, text: "Wi-Fi channel changed from \(wa.channel.map(String.init) ?? "unknown") to \(wb.channel.map(String.init) ?? "unknown")"))
            }
            if let pa = wa.signalPct, let pb = wb.signalPct, abs(pa - pb) >= 20 {
                out.append(.init(level: .info, text: "Wi-Fi signal moved from \(pa)% to \(pb)%"))
            }
        }
        if let ia = a.publicIp, let ib = b.publicIp, ia != ib {
            out.append(.init(level: .info, text: "Public IP changed from \(ia) to \(ib)"))
        }
        if let da = a.dns, let db = b.dns, da.servers != db.servers || da.encrypted != db.encrypted {
            out.append(.init(level: .warn, text: "DNS changed from \(da.servers) to \(db.servers)\(db.encrypted == false ? " (not encrypted)" : "")"))
        }
        return out.sorted { $0.level.rawValue > $1.level.rawValue }
    }

    /// What the chosen sensitivity lets through: Low = open backdoors only, Normal = also things to review,
    /// High = every change.
    static func filter(_ items: [WatchChange], _ sensitivity: AlertSensitivity) -> [WatchChange] {
        switch sensitivity {
        case .low: return items.filter { $0.level == .risk }
        case .normal: return items.filter { $0.level != .info }
        case .high: return items
        }
    }
}
