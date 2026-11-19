import Foundation

/// Claude (Anthropic Messages API), ChatGPT (OpenAI Responses API) and Grok (xAI, OpenAI-compatible
/// Chat Completions) over plain HTTPS. Parsing is a pure function per provider so it can be tested
/// without a network.
public struct ApiProviders: Sendable {
    public var client: ApiClient
    /// Overridable only through this initializer (tests); the shipped app always uses the real hosts.
    var anthropicURL = URL(string: "https://api.anthropic.com/v1/messages")!
    var openaiURL = URL(string: "https://api.openai.com/v1/responses")!
    var xaiURL = URL(string: "https://api.x.ai/v1/chat/completions")!
    var openrouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    public init(client: ApiClient = ApiClient()) { self.client = client }

    init(client: ApiClient, anthropic: URL, openai: URL, xai: URL) {
        self.client = client; anthropicURL = anthropic; openaiURL = openai; xaiURL = xai
    }

    // MARK: parsing

    static func parseClaude(_ json: [String: Any], model: String, allowEmpty: Bool) -> AgentAnswer {
        let served = (json["model"] as? String) ?? model
        let stop = json["stop_reason"] as? String
        if stop == "refusal" {
            let d = json["stop_details"] as? [String: Any]
            var msg = "Claude declined to answer this request"
            if let c = d?["category"] as? String { msg += " (category: \(c))" }
            msg += "."
            if let e = d?["explanation"] as? String { msg += " \(ApiClient.scrub(e, key: nil))" }
            return .failure(msg, model: served)
        }
        let blocks = (json["content"] as? [[String: Any]]) ?? []
        var text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
            .joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if stop == "max_tokens" {
            text = "\(text)\n\n[The answer was cut off at the length limit. Ask a narrower question for the rest.]".trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.isEmpty && !allowEmpty { return .failure("Claude returned an empty answer.", model: served) }
        return AgentAnswer(ok: true, model: served, text: text, error: nil)
    }

    /// The raw Responses API has no `output_text` shortcut (that is an SDK convenience): the text sits in
    /// output[].content[] parts of type "output_text".
    static func parseOpenAI(_ json: [String: Any], model: String, allowEmpty: Bool) -> AgentAnswer {
        let served = (json["model"] as? String) ?? model
        if let e = json["error"] as? [String: Any], let m = e["message"] as? String {
            return .failure("OpenAI error: \(ApiClient.scrub(m, key: nil))", model: served)
        }
        let status = json["status"] as? String
        if status == "failed" { return .failure("OpenAI error: the response failed", model: served) }
        var parts: [String] = []
        var refusal: String?
        for item in (json["output"] as? [[String: Any]]) ?? [] {
            for part in (item["content"] as? [[String: Any]]) ?? [] {
                switch part["type"] as? String {
                case "output_text": if let t = part["text"] as? String { parts.append(t) }
                case "refusal": refusal = refusal ?? (part["refusal"] as? String)
                default: break
                }
            }
        }
        var text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, let r = refusal { return .failure("ChatGPT declined to answer: \(ApiClient.scrub(r, key: nil))", model: served) }
        if status == "incomplete" {
            let reason = ((json["incomplete_details"] as? [String: Any])?["reason"] as? String) ?? "incomplete"
            if text.isEmpty { return allowEmpty ? AgentAnswer(ok: true, model: served, text: "", error: nil)
                                                : .failure("The answer was incomplete (\(reason)).", model: served) }
            text += "\n\n[The answer was cut off (\(reason)). Ask a narrower question for the rest.]"
        }
        if text.isEmpty && !allowEmpty { return .failure("ChatGPT returned an empty answer.", model: served) }
        return AgentAnswer(ok: true, model: served, text: text, error: nil)
    }

    /// Chat Completions format, shared by xAI and OpenRouter.
    static func parseGrok(_ json: [String: Any], model: String, allowEmpty: Bool, name: String = "Grok") -> AgentAnswer {
        let served = (json["model"] as? String) ?? model
        let choice = ((json["choices"] as? [[String: Any]]) ?? []).first
        let message = (choice?["message"] as? [String: Any]) ?? [:]
        if let r = message["refusal"] as? String, !r.isEmpty { return .failure("\(name) declined to answer: \(ApiClient.scrub(r, key: nil))", model: served) }
        var text = ((message["content"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if (choice?["finish_reason"] as? String) == "length", !text.isEmpty {
            text += "\n\n[The answer was cut off at the length limit. Ask a narrower question for the rest.]"
        }
        if text.isEmpty && !allowEmpty { return .failure("\(name) returned an empty answer.", model: served) }
        return AgentAnswer(ok: true, model: served, text: text, error: nil)
    }
}
