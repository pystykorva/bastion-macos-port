import Foundation

/// Where Support messages go. It is read from the app's Info.plist, and package.sh writes it there from the
/// developer's own environment (TESSU_FEEDBACK_EMAIL, TESSU_FEEDBACK_ISSUES_URL) or an untracked
/// `.release.env`. Nothing about it is in the source tree, so a fork that builds from source has no
/// destination: its feedback button is simply absent, and it can never reach the original developer.
public struct FeedbackConfig: Equatable, Sendable {
    public var email: String?
    public var issuesURL: URL?

    public init(email: String? = nil, issuesURL: URL? = nil) {
        self.email = email
        self.issuesURL = issuesURL
    }

    /// Reads the two Info.plist keys. Anything empty, malformed or still a template placeholder is ignored.
    public init(info: [String: Any]?) {
        let e = Self.clean(info?["TessuFeedbackEmail"])
        email = Rx.test("^[^\\s@<>()\\[\\]\\\\,;:\"]+@[^\\s@<>()\\[\\]\\\\,;:\"]+\\.[A-Za-z]{2,}$", e) ? e : nil
        let u = Self.clean(info?["TessuFeedbackIssuesURL"])
        if let url = URL(string: u), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty {
            issuesURL = url
        } else {
            issuesURL = nil
        }
    }

    public static var current: FeedbackConfig { FeedbackConfig(info: Bundle.main.infoDictionary) }

    private static func clean(_ v: Any?) -> String {
        let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.hasPrefix("__") ? "" : s
    }

    public var isConfigured: Bool { email != nil || issuesURL != nil }

    /// Said on the Support screen, so the user knows where their words go before they send them.
    public var destination: String {
        switch (email, issuesURL) {
        case let (e?, u?): return "Messages go to \(e), or to the public issue tracker at \(u.host ?? "")."
        case let (e?, nil): return "Messages go to \(e)."
        case let (nil, u?): return "Messages go to the public issue tracker at \(u.host ?? "")."
        default: return "This build has no feedback address, so nothing can be sent from here. You can still copy the text."
        }
    }

    // MARK: composing

    /// Percent-encoding that is safe inside a mailto: or query value (unreserved characters only).
    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? ""
    }

    /// Mail clients fail on mailto: links beyond roughly 2000 characters, and encoding grows text 3x or more.
    public static let mailtoBudget = 1700
    static let cutNote = "... [shortened: the full text is on your clipboard]"

    public func mailto(subject: String, body: String) -> (url: URL, truncated: Bool)? {
        guard let email = email else { return nil }
        let chars = Array(body)
        var keep = chars.count
        var text = body
        var truncated = false
        while Self.encode(text).count > Self.mailtoBudget && keep > 0 {
            let ratio = Double(Self.mailtoBudget) / Double(Self.encode(text).count)
            keep = max(0, min(keep - 1, Int(Double(keep) * ratio)))
            text = String(chars[..<keep]) + Self.cutNote
            truncated = true
        }
        guard let url = URL(string: "mailto:\(email)?subject=\(Self.encode(subject))&body=\(Self.encode(text))") else { return nil }
        return (url, truncated)
    }

    /// A prefilled "new issue" page on the configured tracker. Browsers accept long URLs, but trackers do not.
    public func issue(title: String, body: String) -> (url: URL, truncated: Bool)? {
        guard let base = issuesURL, var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let cap = 5000
        let truncated = body.count > cap
        let text = truncated ? String(body.prefix(cap)) + Self.cutNote : body
        let existing = c.percentEncodedQuery.map { $0 + "&" } ?? ""
        c.percentEncodedQuery = existing + "title=\(Self.encode(title))&body=\(Self.encode(text))"
        guard let url = c.url else { return nil }
        return (url, truncated)
    }
}
