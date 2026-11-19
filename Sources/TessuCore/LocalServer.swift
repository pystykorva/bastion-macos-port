import Foundation

/// A model server on this Mac or the local network that speaks the OpenAI chat API: LM Studio, Ollama,
/// llama.cpp's server, vLLM, Jan and so on. One provider covers them all; only the address differs.
public enum LocalServer {
    public static let presets: [(name: String, url: String)] = [
        ("LM Studio", "http://localhost:1234/v1"),
        ("Ollama", "http://localhost:11434/v1"),
        ("llama.cpp", "http://localhost:8080/v1"),
        ("vLLM", "http://localhost:8000/v1"),
    ]

    public static let defaultURL = presets[0].url

    /// Loading a model can take a minute or more, so a local request is allowed to wait much longer.
    public static let requestTimeout: TimeInterval = 600
    /// Overall deadline for one question, model load included.
    public static let deadline: TimeInterval = 12 * 60
    /// Reasoning models (Qwen, DeepSeek, gpt-oss ...) spend tokens thinking before the answer, and those count.
    public static let maxOutputTokens = 8000

    public struct Checked: Sendable {
        public var url: URL?
        /// true when the address is this Mac, so nothing in a question can leave it.
        public var loopback = false
        public var error: String?
    }

    /// Accepts "localhost:1234", "http://127.0.0.1:1234/v1/", "http://host:8080/v1/chat/completions".
    public static func validate(_ text: String) -> Checked {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return Checked(error: "Enter the server address, for example \(defaultURL).") }
        if !s.contains("://") { s = "http://" + s }
        guard var c = URLComponents(string: s), let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = c.host, !host.isEmpty else {
            return Checked(error: "That is not a valid http:// or https:// address.")
        }
        if c.user != nil || c.password != nil { return Checked(error: "Put an API key in the key field, not in the address.") }
        c.query = nil; c.fragment = nil
        var path = c.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/chat/completions") { path.removeLast("/chat/completions".count) }
        c.path = path.isEmpty ? "/v1" : path
        guard let url = c.url else { return Checked(error: "That is not a valid address.") }
        return Checked(url: url, loopback: isLoopback(host), error: nil)
    }

    public static func isLoopback(_ host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return h == "localhost" || h.hasSuffix(".localhost") || h == "::1" || h.hasPrefix("127.")
    }

    static func chatURL(_ base: URL) -> URL { base.appendingPathComponent("chat/completions") }
    static func modelsURL(_ base: URL) -> URL { base.appendingPathComponent("models") }

    /// Model ids from a GET /models answer. Skips embedding-only entries, which cannot chat.
    public static func parseModels(_ json: [String: Any]) -> [String] {
        let items = (json["data"] as? [[String: Any]]) ?? (json["models"] as? [[String: Any]]) ?? []
        var out: [String] = []
        for m in items {
            guard let id = (m["id"] as? String) ?? (m["name"] as? String) ?? (m["model"] as? String), !id.isEmpty else { continue }
            if Rx.test("embed|rerank", id, options: .caseInsensitive) || (m["type"] as? String) == "embeddings" { continue }
            if !out.contains(id) { out.append(id) }
        }
        return out
    }

    /// Reasoning some servers put inside the answer text.
    public static func stripThinking(_ text: String) -> String {
        text.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The sentence shown when the server cannot be reached.
    public static func unreachable(_ base: URL) -> String {
        let host = base.host ?? "the server"
        let port = base.port.map { ":\($0)" } ?? ""
        return "Could not reach the local server at \(host)\(port). Start it first: in LM Studio open the Developer tab and turn the server on; for Ollama run `ollama serve`."
    }
}
