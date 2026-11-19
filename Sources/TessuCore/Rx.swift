import Foundation

// Tiny regex and XML helpers. The original engine also used regex-based, namespace-tolerant XML,
// because routers send slightly malformed documents that strict parsers reject.

enum Rx {
    /// First match's capture groups (index 0 = whole match), or nil.
    static func first(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return groups(m, ns)
    }

    static func all(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { groups($0, ns) }
    }

    static func test(_ pattern: String, _ text: String, options: NSRegularExpression.Options = []) -> Bool {
        first(pattern, in: text, options: options) != nil
    }

    private static func groups(_ m: NSTextCheckingResult, _ ns: NSString) -> [String] {
        (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}

enum XML {
    static func decode(_ s: String) -> String {
        var out = s
        for m in Rx.all("<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>", in: out) { out = out.replacingOccurrences(of: m[0], with: m[1]) }
        out = out.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
        for m in Rx.all("&#(\\d+);", in: out) {
            if let n = UInt32(m[1]), let u = Unicode.Scalar(n) { out = out.replacingOccurrences(of: m[0], with: String(Character(u))) }
        }
        for m in Rx.all("&#x([0-9a-fA-F]+);", in: out) {
            if let n = UInt32(m[1], radix: 16), let u = Unicode.Scalar(n) { out = out.replacingOccurrences(of: m[0], with: String(Character(u))) }
        }
        // &amp; last, so "&amp;lt;" decodes to "&lt;" and not to "<".
        return out.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tagPattern(_ name: String) -> String {
        let n = NSRegularExpression.escapedPattern(for: name)
        return "<(?:[\\w-]+:)?\(n)(?:\\s[^>]*)?>([\\s\\S]*?)</(?:[\\w-]+:)?\(n)\\s*>"
    }

    /// First <name>...</name> (any namespace prefix), decoded; nil when missing.
    static func tag(_ xml: String?, _ name: String) -> String? {
        guard let xml = xml, let m = Rx.first(tagPattern(name), in: xml, options: .caseInsensitive) else { return nil }
        return decode(m[1])
    }

    /// Every <name>...</name> block, raw so it can be searched further.
    static func blocks(_ xml: String?, _ name: String) -> [String] {
        guard let xml = xml else { return [] }
        return Rx.all(tagPattern(name), in: xml, options: .caseInsensitive).map { $0[1] }
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
