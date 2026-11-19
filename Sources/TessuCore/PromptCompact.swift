import Foundation

extension PromptBuilder {
    /// Characters of evidence kept per check in the compact form.
    static let compactEvidence = 200

    /// A much smaller snapshot for models with a small context window (local models are often loaded with
    /// 4-8k tokens, and the full snapshot can reach about 15k). It keeps what the answers are built from:
    /// the scan findings, Wi-Fi, DNS, speed and a short device list, and drops the connection list and the
    /// per-check error notes. Everything the privacy filter removes is still removed.
    public static func compactSnapshot(_ s: SnapshotInput, now: Date = Date()) -> JSON {
        guard case .object(let fields) = minimizeSnapshot(s, now: now) else { return .null }
        var out: [(String, JSON)] = []
        for (key, value) in fields {
            switch key {
            case "connections":
                out.append((key, .null))
            case "devices":
                out.append((key, trimItems(value, to: 10)))
            case "wifiSurvey":
                out.append((key, trimItems(value, key: "congestion", to: 8)))
            default:
                out.append((key, value))
            }
        }
        return JSON.object(out).mapStrings { $0.count > compactEvidence ? String($0.prefix(compactEvidence - 1)) + "…" : $0 }
            .withoutKeys(["errors"])
    }

    private static func trimItems(_ v: JSON, key: String = "items", to n: Int) -> JSON {
        guard case .object(var f) = v, let i = f.firstIndex(where: { $0.0 == key }), case .array(let a) = f[i].1 else { return v }
        f[i].1 = .array(Array(a.prefix(n)))
        if let si = f.firstIndex(where: { $0.0 == "shown" }) { f[si].1 = .number(Double(min(n, a.count))) }
        return .object(f)
    }

    /// The text sent to a small-context model.
    public static func compactMessage(question: String, snapshot: SnapshotInput, now: Date = Date()) -> String {
        let q = String(question.replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(Prompt.Limits.question))
        return [
            "Network snapshot measured by Tessu on this computer (JSON, privacy-minimized, shortened for a small model):",
            "<snapshot>", compactSnapshot(snapshot, now: now).serialized(), "</snapshot>", "",
            "Question from the user:", q,
        ].joined(separator: "\n")
    }
}

extension JSON {
    /// Removes the named keys at every depth.
    func withoutKeys(_ names: Set<String>) -> JSON {
        switch self {
        case .object(let o): return .object(o.filter { !names.contains($0.0) }.map { ($0.0, $0.1.withoutKeys(names)) })
        case .array(let a): return .array(a.map { $0.withoutKeys(names) })
        default: return self
        }
    }
}
