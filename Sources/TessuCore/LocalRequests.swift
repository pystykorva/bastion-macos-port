import Foundation

extension ApiProviders {
    /// Asks the local server. `model` "default" or "" means "whatever the server has loaded": LM Studio
    /// answers with its loaded model, and Ollama needs a name, which Test and the picker fill in.
    public func askLocal(base: URL, apiKey: String?, model: String, system: String, userText: String,
                         allowEmpty: Bool = false, maxTokens: Int = LocalServer.maxOutputTokens) async -> AgentAnswer {
        var headers: [String: String] = [:]
        if let k = apiKey, !k.isEmpty { headers["Authorization"] = "Bearer \(k)" }
        var msgs: [[String: String]] = []
        if !system.isEmpty { msgs.append(["role": "system", "content": system]) }
        msgs.append(["role": "user", "content": userText])
        var body: [String: Any] = ["messages": msgs, "stream": false, "max_tokens": maxTokens]
        if !model.isEmpty && model != "default" { body["model"] = model }
        do {
            let r = try await client.post(LocalServer.chatURL(base), headers: headers, body: body, timeout: LocalServer.requestTimeout)
            if (200..<300).contains(r.status), let json = r.json {
                return Self.parseLocal(json, model: model, allowEmpty: allowEmpty)
            }
            return .failure(Self.localFailure(status: r.status, reply: r, key: apiKey), model: model)
        } catch let e as URLError where e.code == .cancelled && Task.isCancelled {
            return .failure("Cancelled.", model: model)
        } catch let e as URLError where e.code == .cancelled || e.code == .networkConnectionLost || e.code == .badServerResponse {
            // Not cancelled by the user: the server hung up. LM Studio does this when the model is unloaded or reloaded mid-answer.
            return .failure("The server closed the connection before it finished answering. If you unloaded or reloaded the model meanwhile, ask again.", model: model)
        } catch let e as URLError where e.code == .cannotConnectToHost || e.code == .cannotFindHost {
            return .failure(LocalServer.unreachable(base), model: model)
        } catch {
            return .failure(ApiClient.describe(status: 0, reply: nil, error: error, vendor: "the local server", key: apiKey), model: model)
        }
    }

    /// Chat Completions answer from a local server. Handles reasoning models: thinking tokens are not part
    /// of the answer, and a model that used its whole budget thinking gets a specific explanation.
    static func parseLocal(_ json: [String: Any], model: String, allowEmpty: Bool) -> AgentAnswer {
        var j = json
        if var choices = j["choices"] as? [[String: Any]], var c = choices.first, var m = c["message"] as? [String: Any],
           let content = m["content"] as? String {
            m["content"] = LocalServer.stripThinking(content)
            c["message"] = m; choices[0] = c; j["choices"] = choices
        }
        let r = parseGrok(j, model: model, allowEmpty: allowEmpty, name: "The local model")
        if !r.ok, let c = (json["choices"] as? [[String: Any]])?.first,
           let m = c["message"] as? [String: Any], !((m["reasoning_content"] as? String) ?? (m["reasoning"] as? String) ?? "").isEmpty {
            return .failure("The model spent its whole answer budget thinking and never wrote a reply. Ask again, use a smaller reasoning effort, or pick a non-reasoning model.", model: r.model)
        }
        return r
    }

    static func localFailure(status: Int, reply: ApiClient.Reply, key: String?) -> String {
        let detail = ApiClient.serverMessage(reply).map { ApiClient.scrub($0, key: key) } ?? ""
        let lower = detail.lowercased()
        if lower.contains("no models loaded") || lower.contains("model not loaded") || lower.contains("no model") {
            return "The server has no model loaded. Load one in LM Studio (or pick one in Settings), then try again."
        }
        if lower.contains("context") && (lower.contains("length") || lower.contains("exceed") || lower.contains("overflow") || lower.contains("too long")) {
            return "The snapshot is longer than this model's context window. Raise the context length when loading the model, or ask a narrower question. (\(detail))"
        }
        switch status {
        case 401, 403: return "The local server rejected the key. Check the key in Settings, or clear it if the server needs none."
        case 404: return "The server does not know that model, or this address is not an OpenAI-style API (it should end in /v1). \(detail)"
        default: return "The local server answered \(status)\(detail.isEmpty ? "" : ": \(detail)")"
        }
    }

    /// GET /models: ids of the models the server offers (LM Studio: the loaded ones, plus downloaded ones).
    public func localModels(base: URL, apiKey: String?) async -> (models: [String], error: String?) {
        var req = URLRequest(url: LocalServer.modelsURL(base), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        if let k = apiKey, !k.isEmpty { req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await client.session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                return ([], status == 401 || status == 403 ? "The server needs an API key." : "The server answered \(status) for /models. Is the address an OpenAI-style API ending in /v1?")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ([], "The server answered, but not with a model list. Is the address an OpenAI-style API ending in /v1?")
            }
            return (LocalServer.parseModels(json), nil)
        } catch let e as URLError where e.code == .cannotConnectToHost || e.code == .timedOut || e.code == .cannotFindHost {
            return ([], LocalServer.unreachable(base))
        } catch {
            return ([], "Could not read the model list: \(errMsg(error))")
        }
    }
}
