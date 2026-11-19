import Foundation

extension ApiProviders {
    /// Asks one API provider. `allowEmpty` is for connectivity tests: a completed call proves the key and
    /// model work even when the model answered with nothing.
    public func ask(_ id: ProviderID, apiKey: String, model: String, system: String, userText: String,
                    maxTokens: Int = 16000, allowEmpty: Bool = false, timeout: TimeInterval? = nil) async -> AgentAnswer {
        let vendor: String
        let url: URL
        let headers: [String: String]
        let body: [String: Any]
        switch id {
        case .claude:
            vendor = "Anthropic"; url = anthropicURL
            headers = ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
            body = ["model": model, "max_tokens": maxTokens, "system": system, "messages": [["role": "user", "content": userText]]]
        case .openai:
            vendor = "OpenAI"; url = openaiURL
            headers = ["Authorization": "Bearer \(apiKey)"]
            var b: [String: Any] = ["model": model, "input": userText, "max_output_tokens": maxTokens]
            if !system.isEmpty { b["instructions"] = system }
            body = b
        case .grok, .openrouter:
            vendor = id == .grok ? "xAI" : "OpenRouter"
            url = id == .grok ? xaiURL : openrouterURL
            var h = ["Authorization": "Bearer \(apiKey)"]
            if id == .openrouter { h["X-Title"] = "Tessu" } // names the app on OpenRouter's usage page
            headers = h
            var msgs: [[String: String]] = []
            if !system.isEmpty { msgs.append(["role": "system", "content": system]) }
            msgs.append(["role": "user", "content": userText])
            body = ["model": model, "messages": msgs]
        case .local:
            return .failure("The local server is asked through askLocal.", model: model)
        case .claudeCli, .codexCli:
            return .failure("\(id.name) uses your subscription login, not an API key.", model: model)
        }
        // One retry on a transient failure (rate limit, server error, dropped connection), like the SDKs did.
        var last: AgentAnswer = .failure("Request failed.", model: model)
        for attempt in 0..<2 {
            do {
                let r = try await client.post(url, headers: headers, body: body, timeout: timeout)
                if (200..<300).contains(r.status), let json = r.json {
                    switch id {
                    case .claude: return Self.parseClaude(json, model: model, allowEmpty: allowEmpty)
                    case .openai: return Self.parseOpenAI(json, model: model, allowEmpty: allowEmpty)
                    default: return Self.parseGrok(json, model: model, allowEmpty: allowEmpty, name: id.name)
                    }
                }
                last = .failure(ApiClient.describe(status: r.status, reply: r, error: nil, vendor: vendor, key: apiKey), model: model)
                if !(r.status == 429 || r.status >= 500) { return last }
            } catch {
                last = .failure(ApiClient.describe(status: 0, reply: nil, error: error, vendor: vendor, key: apiKey), model: model)
                if (error as? URLError)?.code == .cancelled || Task.isCancelled { return last }
            }
            if attempt == 0 { try? await Task.sleep(nanoseconds: 800_000_000) }
        }
        return last
    }

    /// Connectivity check with a tiny question.
    public func test(_ id: ProviderID, apiKey: String, model: String) async -> AgentAnswer {
        await ask(id, apiKey: apiKey, model: model, system: id == .claude ? "You are a connectivity check." : "",
                  userText: "Reply with OK", maxTokens: id == .claude ? 1024 : 512, allowEmpty: true, timeout: 60)
    }
}
