import Foundation

extension PromptBuilder {
    /// The minimized snapshot as JSON.
    public static func minimizeSnapshot(_ s: SnapshotInput, now: Date = Date()) -> JSON {
        let out: JSON = .object([
            ("takenAt", iso(now)),
            ("platform", .string("darwin")),
            ("privacy", .string("Removed before sending: full MAC addresses, device names, Wi-Fi network names, BSSIDs, this computer's name, last part of the public IP. Lists are capped. null means not measured or not available.")),
            ("overview", overview(s.overview)),
            ("devices", devices(s.devices)),
            ("connections", connections(s.connections)),
            ("scan", scan(s.scan)),
            ("wifi", wifi(s.wifi)),
            ("wifiSurvey", survey(s.survey)),
            ("dns", dns(s.dns)),
            ("speed", speed(s.speed)),
        ])
        // Belt and braces: identifying strings must not survive inside free text (scan evidence, errors,
        // hosts). Values are replaced inside string values only, so the structure is never touched.
        let secrets = collectSecrets(s)
        var result = secrets.isEmpty ? out : out.mapStrings { text in
            var v = text
            for (secret, label) in secrets where v.contains(secret) { v = v.replacingOccurrences(of: secret, with: label) }
            return v
        }
        // Keep the request small: trim the longest lists until it fits.
        for (section, minimum) in [("connections", 10), ("devices", 10)] {
            while result.serialized().count > Prompt.Limits.totalChars, let cut = shrink(result, section: section, minimum: minimum) {
                result = cut
            }
        }
        return result
    }

    /// One list shortened by about 30 %, or nil when it is already at its minimum.
    private static func shrink(_ doc: JSON, section: String, minimum: Int) -> JSON? {
        guard case .object(var fields) = doc,
              let idx = fields.firstIndex(where: { $0.0 == section }),
              case .object(var sec) = fields[idx].1,
              let ii = sec.firstIndex(where: { $0.0 == "items" }),
              case .array(let items) = sec[ii].1, items.count > minimum else { return nil }
        let keep = max(minimum, Int(Double(items.count) * 0.7))
        sec[ii].1 = .array(Array(items.prefix(keep)))
        if let si = sec.firstIndex(where: { $0.0 == "shown" }) { sec[si].1 = .number(Double(keep)) }
        fields[idx].1 = .object(sec)
        return .object(fields)
    }

    /// The text sent to the provider: snapshot plus question.
    public static func userMessage(question: String, snapshot: SnapshotInput, now: Date = Date()) -> String {
        let q = String(question.replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(Prompt.Limits.question))
        return [
            "Network snapshot measured by Tessu on this computer (JSON, privacy-minimized):",
            "<snapshot>", minimizeSnapshot(snapshot, now: now).serialized(), "</snapshot>", "",
            "Question from the user:", q,
        ].joined(separator: "\n")
    }
}
