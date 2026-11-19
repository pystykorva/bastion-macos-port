import Foundation

/// A JSON value tree. The minimized snapshot is built as plain data, so only whitelisted fields can
/// ever reach it, and string scrubbing can walk it without touching the structure.
public indirect enum JSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([(String, JSON)])

    public static func == (a: JSON, b: JSON) -> Bool { a.serialized() == b.serialized() }

    /// Stable output (keys keep insertion order), like JSON.stringify.
    public func serialized(pretty: Bool = false) -> String {
        var out = ""
        write(&out, pretty: pretty, depth: 0)
        return out
    }

    private static func quote(_ s: String) -> String {
        var o = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": o += "\\\""
            case "\\": o += "\\\\"
            case "\n": o += "\\n"
            case "\r": o += "\\r"
            case "\t": o += "\\t"
            default:
                if u.value < 0x20 { o += String(format: "\\u%04x", u.value) } else { o.unicodeScalars.append(u) }
            }
        }
        return o + "\""
    }

    private func write(_ out: inout String, pretty: Bool, depth: Int) {
        let nl = pretty ? "\n" + String(repeating: "  ", count: depth + 1) : ""
        let end = pretty ? "\n" + String(repeating: "  ", count: depth) : ""
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .string(let s): out += JSON.quote(s)
        case .array(let a):
            if a.isEmpty { out += "[]"; return }
            out += "["
            for (i, v) in a.enumerated() { out += (i > 0 ? "," : "") + nl; v.write(&out, pretty: pretty, depth: depth + 1) }
            out += end + "]"
        case .object(let o):
            if o.isEmpty { out += "{}"; return }
            out += "{"
            for (i, kv) in o.enumerated() {
                out += (i > 0 ? "," : "") + nl + JSON.quote(kv.0) + (pretty ? ": " : ":")
                kv.1.write(&out, pretty: pretty, depth: depth + 1)
            }
            out += end + "}"
        }
    }

    // MARK: building helpers

    static func str(_ s: String?, max: Int = Prompt.Limits.text) -> JSON {
        guard let s = s else { return .null }
        return .string(PromptBuilder.clean(s, max: max))
    }
    static func num(_ n: Int?) -> JSON { n.map { .number(Double($0)) } ?? .null }
    static func num(_ n: Double?) -> JSON { n.flatMap { $0.isFinite ? .number(($0 * 100).rounded() / 100) : nil } ?? .null }
    static func bool(_ b: Bool?) -> JSON { b.map { .bool($0) } ?? .null }

    /// Applies `transform` to every string value, leaving keys and structure alone. A "privacy" key is exempt:
    /// that sentence names the very things it removes.
    func mapStrings(_ transform: (String) -> String, key: String? = nil) -> JSON {
        switch self {
        case .string(let s): return key == "privacy" ? self : .string(transform(s))
        case .array(let a): return .array(a.map { $0.mapStrings(transform) })
        case .object(let o): return .object(o.map { ($0.0, $0.1.mapStrings(transform, key: $0.0)) })
        default: return self
        }
    }

    subscript(key: String) -> JSON? {
        if case .object(let o) = self { return o.first { $0.0 == key }?.1 }
        return nil
    }
}
