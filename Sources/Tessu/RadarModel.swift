import SwiftUI
import TessuCore

/// Geometry of the exposure radar, kept apart from drawing so it can be tested and so the list and the
/// graphic always agree. Every check is one beacon: its ANGLE is its category, its DISTANCE from the
/// router at the centre is how reachable it is (open findings sit near the WAN rim, sealed ones close
/// to the core), and its COLOUR and SHAPE are its status. Nothing is invented.
struct RadarBeacon: Identifiable, Equatable {
    var id: String
    var title: String
    var short: String
    var status: CheckStatus
    var angle: Double      // radians, 0 = right, increasing clockwise (screen space)
    var radius: Double     // 0...1 of the disc
    var checking: Bool
}

enum RadarModel {
    /// Fixed slot order around the disc, so a given check is always in the same place.
    static let order = ["tr069", "upnp", "dns-plaintext", "admin-default", "wps", "telnet", "ssh",
                        "web-admin-http", "location-map", "mac-privacy", "wifi-security", "unknown-devices"]

    static let short: [String: String] = [
        "tr069": "TR-069", "upnp": "UPnP", "dns-plaintext": "DNS", "admin-default": "Admin login", "wps": "WPS",
        "telnet": "Telnet", "ssh": "SSH", "web-admin-http": "HTTP admin", "location-map": "Location maps",
        "mac-privacy": "MAC privacy", "wifi-security": "Wi-Fi security", "unknown-devices": "Devices",
    ]

    /// The more reachable a finding, the closer it sits to the WAN edge.
    static func radius(_ status: CheckStatus, checking: Bool) -> Double {
        if checking { return 0.52 }
        switch status {
        case .risk: return 0.84
        case .warn: return 0.67
        case .unknown: return 0.52
        case .ok: return 0.37
        }
    }

    /// Starts at the top (12 o'clock) and goes clockwise.
    static func angle(for id: String) -> Double {
        let slot: Double
        if let i = order.firstIndex(of: id) {
            slot = Double(i) / Double(order.count) * 360 + 8
        } else {
            // A check this build does not know still gets a stable place.
            var h: UInt32 = 2166136261
            for b in id.utf8 { h ^= UInt32(b); h = h &* 16777619 }
            slot = Double(h) / Double(UInt32.max) * 360
        }
        return (-90 + slot) * .pi / 180
    }

    /// One beacon per check that has been (or is being) tested. Pending checks are not drawn.
    static func beacons(report: ScanReport?, progress: [String: ScanProgress], scanning: Bool) -> [RadarBeacon] {
        var out: [RadarBeacon] = []
        let byId = Dictionary((report?.checks ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for def in Scan.checks {
            if scanning {
                if let p = progress[def.id] {
                    if let status = p.status {
                        out.append(make(def.id, def.title, status, checking: false))
                    } else {
                        out.append(make(def.id, def.title, .unknown, checking: true))
                    }
                }
            } else if let c = byId[def.id] {
                out.append(make(def.id, c.title, c.status, checking: false))
            }
        }
        return out
    }

    private static func make(_ id: String, _ title: String, _ status: CheckStatus, checking: Bool) -> RadarBeacon {
        RadarBeacon(id: id, title: title, short: short[id] ?? title, status: status,
                    angle: angle(for: id), radius: radius(status, checking: checking), checking: checking)
    }

    /// Point of a beacon inside a square of side `size` centred on its middle, with a small margin for labels.
    static func point(_ b: RadarBeacon, in size: CGSize, inset: CGFloat = 0.0) -> CGPoint {
        let r = min(size.width, size.height) / 2 * (0.92 - inset)
        return CGPoint(x: size.width / 2 + CGFloat(cos(b.angle) * b.radius) * r,
                       y: size.height / 2 + CGFloat(sin(b.angle) * b.radius) * r)
    }

    /// The beacon closest to a point, within `limit` points, for hover and click.
    static func nearest(to p: CGPoint, in size: CGSize, beacons: [RadarBeacon], limit: CGFloat = 26) -> RadarBeacon? {
        var best: (RadarBeacon, CGFloat)?
        for b in beacons {
            let q = point(b, in: size)
            let d = hypot(q.x - p.x, q.y - p.y)
            if d <= limit, d < (best?.1 ?? .infinity) { best = (b, d) }
        }
        return best?.0
    }

    /// Plain-language summary for VoiceOver.
    static func summary(_ beacons: [RadarBeacon]) -> String {
        let c = Dictionary(grouping: beacons, by: \.status).mapValues(\.count)
        return "Exposure radar. \(c[.risk] ?? 0) open, \(c[.warn] ?? 0) to review, \(c[.unknown] ?? 0) unknown, \(c[.ok] ?? 0) sealed."
    }
}
