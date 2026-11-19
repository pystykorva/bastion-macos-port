import Foundation

/// Builds the privacy-minimized snapshot sent with every AI question. A whitelist: anything not copied
/// here never leaves the machine. Full MACs, device names, Wi-Fi names, BSSIDs, this computer's name and
/// the last part of the public IP are removed, lists are capped, and identifying strings are scrubbed
/// from free text as well.
public enum PromptBuilder {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func iso(_ d: Date?) -> JSON { d.map { .string(isoFormatter.string(from: $0)) } ?? .null }

    /// Control characters become spaces, MAC addresses become "[mac]", long text is shortened.
    static func clean(_ value: String, max: Int = Prompt.Limits.text) -> String {
        var s = value.unicodeScalars.map { ($0.value < 0x20 || $0.value == 0x7f) ? " " : String($0) }.joined()
        s = s.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: "\\b[0-9a-fA-F]{2}(?:[:-][0-9a-fA-F]{2}){5}\\b", with: "[mac]", options: .regularExpression)
        return s.count > max ? String(s.prefix(max - 1)) + "…" : s
    }

    static func errors(_ list: [String]) -> JSON {
        .array(list.prefix(Prompt.Limits.errors).map { JSON.str($0) }.filter { $0 != .null })
    }

    // MARK: sections

    static func overview(_ o: NetworkOverview?) -> JSON {
        guard let o = o else { return .null }
        return .object([
            ("local", .object([
                ("ip", .str(o.local.ip, max: 64)), ("iface", .str(o.local.iface, max: 64)), ("macRandomized", .bool(o.local.macRandomized)),
            ])),
            ("gateway", .object([("ip", .str(o.gateway.ip, max: 64)), ("vendor", .str(o.gateway.vendor, max: 80))])),
            ("publicIp", Prompt.maskPublicIp(o.publicIp).map { .string($0) } ?? .null),
            ("errors", errors(o.errors)),
        ])
    }

    static func devices(_ list: [Device]?) -> JSON {
        guard let list = list else { return .null }
        let items = list.prefix(Prompt.Limits.devices).map { d -> JSON in
            .object([
                ("ip", .str(d.ip, max: 64)), ("vendor", .str(d.vendor, max: 80)), ("randomizedMac", .bool(d.randomizedMac)),
                ("isGateway", .bool(d.isGateway)), ("isThisComputer", .bool(d.isThisComputer)),
                ("kind", Prompt.deviceKind(d.hostname).map { .string($0) } ?? .null),
            ])
        }
        return .object([("total", .num(list.count)), ("shown", .num(items.count)), ("items", .array(items))])
    }

    /// Identical destinations are grouped so the cap keeps more distinct information.
    static func connections(_ list: [Connection]?) -> JSON {
        guard let list = list else { return .null }
        struct Group { var c: Connection; var count: Int }
        var groups: [String: Group] = [:]
        var order: [String] = []
        for c in list {
            let key = "\(c.process ?? "")|\(c.proto)|\(c.remoteIp)|\(c.remotePort)|\(c.state ?? "")"
            if groups[key] != nil { groups[key]!.count += 1 } else { groups[key] = Group(c: c, count: 1); order.append(key) }
        }
        let top = order.compactMap { groups[$0] }.sorted { $0.count > $1.count }.prefix(Prompt.Limits.connections)
        let items = top.map { g -> JSON in
            .object([
                ("process", .str(g.c.process, max: 80)), ("protocol", .str(g.c.proto, max: 8)), ("remoteIp", .str(g.c.remoteIp, max: 64)),
                ("remotePort", .num(g.c.remotePort)), ("state", .str(g.c.state, max: 24)), ("count", .num(g.count)),
            ])
        }
        return .object([("total", .num(list.count)), ("shown", .num(items.count)), ("items", .array(Array(items)))])
    }

    static func scan(_ s: ScanReport?) -> JSON {
        guard let s = s else { return .null }
        let checks = s.checks.prefix(Prompt.Limits.checks).map { c -> JSON in
            .object([
                ("id", .str(c.id, max: 40)), ("title", .str(c.title)), ("status", .str(c.status.rawValue, max: 16)),
                ("severity", .str(c.severity.rawValue, max: 16)), ("evidence", .str(c.evidence, max: 400)),
                ("fix", .str(c.fix?.label)),
            ])
        }
        let upnp = s.upnpMappings.prefix(Prompt.Limits.upnp).map { m -> JSON in
            .object([
                ("protocol", .str(m.proto, max: 8)), ("externalPort", .num(m.externalPort)), ("internalClient", .str(m.internalClient, max: 64)),
                ("internalPort", .num(m.internalPort)), ("description", .str(m.description, max: 120)),
            ])
        }
        let ports = s.openPorts.prefix(Prompt.Limits.openPorts).map { p -> JSON in
            .object([("port", .num(p.port)), ("service", .str(p.service, max: 40))])
        }
        return .object([
            ("startedAt", iso(s.startedAt)), ("finishedAt", iso(s.finishedAt)), ("score", .num(s.score)),
            ("checks", .array(Array(checks))), ("upnpMappings", .array(Array(upnp))), ("upnpMappingsTotal", .num(s.upnpMappings.count)),
            ("openPorts", .array(Array(ports))), ("errors", errors(s.errors)),
        ])
    }
}
