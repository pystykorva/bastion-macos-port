import Foundation

extension PromptBuilder {
    static func wifi(_ w: WifiInfo?) -> JSON {
        guard let w = w else { return .null }
        return .object([
            ("supported", .bool(w.supported)), ("connected", .bool(w.ssid.map { !$0.isEmpty })),
            ("band", .str(w.band?.rawValue, max: 8)), ("channel", .num(w.channel)), ("widthMHz", .num(w.widthMHz)),
            ("rssi", .num(w.rssi)), ("signalPct", .num(w.signalPct)), ("rxMbps", .num(w.rxMbps)), ("txMbps", .num(w.txMbps)),
            ("security", .str(w.security, max: 60)), ("nomap", .bool(w.nomap)), ("errors", errors(w.errors)),
        ])
    }

    static func survey(_ s: WifiSurvey?) -> JSON {
        guard let s = s else { return .null }
        let congestion = s.congestion.prefix(Prompt.Limits.congestion).map { c -> JSON in
            .object([("channel", .num(c.channel)), ("band", .str(c.band.rawValue, max: 8)), ("count", .num(c.count))])
        }
        let rec: JSON = s.recommendation.map { r in
            .object([
                ("channel", .num(r.channel)), ("band", .str(r.band.rawValue, max: 8)), ("reason", .str(r.reason)),
                ("neighboursNow", .num(r.neighboursNow)), ("neighboursThere", .num(r.neighboursThere)),
            ])
        } ?? .null
        return .object([
            ("supported", .bool(s.supported)), ("networksSeen", .num(s.networks.count)),
            ("current", .object([("channel", .num(s.currentChannel)), ("band", .str(s.currentBand?.rawValue, max: 8))])),
            ("congestion", .array(Array(congestion))), ("recommendation", rec), ("errors", errors(s.errors)),
        ])
    }

    static func dns(_ d: DnsStatus?) -> JSON {
        guard let d = d else { return .null }
        return .object([
            ("servers", .array(d.servers.prefix(8).map { JSON.str($0, max: 64) })), ("gatewayIsResolver", .bool(d.gatewayIsResolver)),
            ("encrypted", .bool(d.encrypted)), ("provider", .str(d.provider, max: 60)), ("errors", errors(d.errors)),
        ])
    }

    static func speed(_ s: SpeedResult?) -> JSON {
        guard let s = s else { return .null }
        return .object([
            ("pingMs", .num(s.pingMs)), ("jitterMs", .num(s.jitterMs)), ("downMbps", .num(s.downMbps)), ("upMbps", .num(s.upMbps)),
            ("server", .str(s.server, max: 80)), ("at", iso(s.at)), ("errors", errors(s.errors)),
        ])
    }

    /// Identifying strings removed from all free text, longest first. Generic device words and very
    /// short values are skipped so ordinary text is not mangled.
    static func collectSecrets(_ s: SnapshotInput) -> [(secret: String, label: String)] {
        var found: [String: String] = [:]
        func add(_ value: String?, _ label: String) {
            guard let v = value?.trimmingCharacters(in: .whitespaces), v.count >= 4, v.count <= 200,
                  !Prompt.deviceWords.contains(v.lowercased()), found[v] == nil else { return }
            found[v] = label
        }
        func addHost(_ h: String?, _ label: String) {
            add(h, label)
            if let h = h, h.contains(".") { add(String(h.split(separator: ".").first ?? ""), label) }
        }
        if let ip = s.overview?.publicIp?.trimmingCharacters(in: .whitespaces), !ip.isEmpty {
            found[ip] = Prompt.maskPublicIp(ip) ?? "masked"
        }
        addHost(s.overview?.hostname, "[hostname]")
        add(s.wifi?.ssid, "[ssid]")
        add(s.wifi?.bssid, "[bssid]")
        for d in (s.devices ?? []).prefix(500) { addHost(d.hostname, "[device-name]") }
        for n in (s.survey?.networks ?? []).prefix(200) { add(n.ssid, "[ssid]") }
        return found.map { ($0.key, $0.value) }.sorted { $0.0.count > $1.0.count }
    }
}
