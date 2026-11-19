import Foundation

extension Agents {
    /// Asks a provider about the current network. The question and a privacy-minimized snapshot are sent;
    /// nothing else. One question per provider at a time.
    public func ask(_ id: ProviderID, question: String, snapshot: SnapshotInput) async -> AgentAnswer {
        let model = currentModel(id)
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return .failure("Type a question first.", model: model) }
        var apiKey: String?
        if !id.isCLI && id != .local {
            let k = keyOrReason(id)
            if let e = k.error { return .failure(e, model: model) }
            apiKey = k.key
        }
        guard let token = begin(id) else { return .failure("\(id.name) is still answering the previous question.", model: model) }
        defer { end(id, token) }
        if id == .local { return await askLocal(question: q, snapshot: snapshot, token: token, test: false) }

        let userText = PromptBuilder.userMessage(question: q, snapshot: snapshot)
        return await withDeadline(token, model: model, id: id) { [self] in
            if id.isCLI { return await cli.ask(id, model: model, system: Prompt.system, userText: userText, cancel: token) }
            return await api.ask(id, apiKey: apiKey ?? "", model: model, system: Prompt.system, userText: userText)
        }
    }

    /// Connectivity check: does this key / CLI work with this model?
    public func test(_ id: ProviderID) async -> AgentAnswer {
        let model = currentModel(id)
        var apiKey: String?
        if !id.isCLI && id != .local {
            let k = keyOrReason(id)
            if let e = k.error { return .failure(e, model: model) }
            apiKey = k.key
        }
        guard let token = begin(id) else { return .failure("\(id.name) is still answering the previous question.", model: model) }
        defer { end(id, token) }
        if id == .local { return await askLocal(question: "", snapshot: SnapshotInput(), token: token, test: true) }
        return await withDeadline(token, model: model, id: id) { [self] in
            if id.isCLI { return await cli.test(id, model: model, cancel: token) }
            return await api.test(id, apiKey: apiKey ?? "", model: model)
        }
    }

    /// Runs `work`, giving up after the overall deadline or when the token is cancelled.
    func withDeadline(_ token: CancelToken, model: String, id: ProviderID, seconds: TimeInterval = Agents.deadline,
                      _ work: @escaping @Sendable () async -> AgentAnswer) async -> AgentAnswer {
        let result: AgentAnswer = await withTaskGroup(of: AgentAnswer?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
                token.cancel()
                return .failure("\(id.name) did not answer within \(Int(seconds / 60)) minutes. Try again, or pick a faster model.", model: model)
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failure("No answer.", model: model)
        }
        if token.isCancelled && !result.ok && result.error != nil && !(result.error ?? "").contains("did not answer within") {
            return .failure("Cancelled.", model: result.model)
        }
        return result
    }

    /// Exactly what an ask would send with a question, for the Settings preview. Nothing leaves the machine.
    public func preview(_ snapshot: SnapshotInput, compact: Bool = false) -> (snapshot: String, system: String) {
        let json = compact ? PromptBuilder.compactSnapshot(snapshot) : PromptBuilder.minimizeSnapshot(snapshot)
        return (json.serialized(pretty: true), Prompt.system)
    }
}
