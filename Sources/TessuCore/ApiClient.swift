import Foundation

/// Shared plumbing for the three HTTPS providers. Base URLs are fixed in code (never read from the
/// environment), so a stray variable cannot redirect a request that carries an API key.
public struct ApiClient: Sendable {
    public var session: URLSession
    public var timeout: TimeInterval

    public init(session: URLSession = ApiClient.makeSession(), timeout: TimeInterval = 180) {
        self.session = session
        self.timeout = timeout
    }

    /// No cookies, no cache, no credential storage: nothing about a request survives it.
    public static func makeSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }

    public struct Reply: Sendable {
        public var status: Int
        public var json: [String: Any]?
        public var body: String
    }

    /// POSTs JSON. Throws URLError on transport problems (timeout, offline, cancelled).
    func post(_ url: URL, headers: [String: String], body: [String: Any], timeout: TimeInterval? = nil) async throws -> Reply {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout ?? self.timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return Reply(status: status, json: try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                     body: String(decoding: data.prefix(4000), as: UTF8.self))
    }

    /// Redacts the key (and anything that looks like one) from text that may be shown to the user.
    public static func scrub(_ text: String, key: String?) -> String {
        var s = text
        if let k = key, !k.isEmpty { s = s.replacingOccurrences(of: k, with: "[key]") }
        s = s.replacingOccurrences(of: "\\b(sk-ant-|sk-|xai-)[A-Za-z0-9_\\-*]{4,}", with: "[key]", options: .regularExpression)
        return String(s.prefix(400))
    }

    /// The provider's own message from a JSON error body, if there is one.
    static func serverMessage(_ r: Reply) -> String? {
        if let e = r.json?["error"] as? [String: Any], let m = e["message"] as? String { return m }
        if let m = r.json?["error"] as? String { return m }
        return r.json?["message"] as? String
    }

    /// Plain-sentence description of a failed request, with the vendor's name in it.
    static func describe(status: Int, reply: Reply?, error: Error?, vendor: String, key: String?) -> String {
        if let e = error as? URLError {
            switch e.code {
            case .timedOut: return "The request to \(vendor) timed out. Try again, or pick a faster model."
            case .cancelled: return "Cancelled."
            default: return "Could not reach \(vendor). Check your internet connection, firewall or proxy."
            }
        }
        if let e = error { return "Request failed: \(scrub(errMsg(e), key: key))" }
        let detail = reply.flatMap(serverMessage).map { scrub($0, key: key) } ?? ""
        switch status {
        case 401: return "That API key was rejected by \(vendor). Check that it is copied completely and still active."
        case 403: return "This API key is not allowed to use that model on \(vendor). Pick another model or check the key's permissions."
        case 404: return "That model was not found on \(vendor) for this key. Pick another model."
        case 429: return "\(vendor) rate limit or quota reached. Wait a minute and try again, or check your billing."
        case 400: return "\(vendor) rejected the request: \(detail.isEmpty ? "bad request" : detail)"
        default: return "\(vendor) error \(status)\(detail.isEmpty ? "" : ": \(detail)")"
        }
    }
}
