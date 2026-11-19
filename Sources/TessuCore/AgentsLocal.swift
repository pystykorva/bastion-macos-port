import Foundation

/// The local-server provider's settings and calls. The address is not secret and lives in UserDefaults;
/// an optional key (most local servers need none) is kept in the Keychain.
extension Agents {
    public var localAddress: String { keystore.localURL ?? LocalServer.defaultURL }

    /// The current address, checked. A non-loopback address needs the user's explicit approval, because
    /// a question would then leave this Mac.
    public func localTarget() -> (url: URL?, error: String?) {
        let c = LocalServer.validate(localAddress)
        guard let url = c.url else { return (nil, c.error) }
        if !c.loopback && keystore.localRemoteApproved != url.absoluteString {
            return (nil, "\(url.host ?? "That server") is not on this Mac, so a question (without Wi-Fi names, device names or MACs) would leave it. Confirm the address in Settings to allow it.")
        }
        return (url, nil)
    }

    /// nil = saved. `approveRemote` records that the user accepted a non-loopback address.
    public func setLocalAddress(_ text: String, approveRemote: Bool = false) -> String? {
        let c = LocalServer.validate(text)
        guard let url = c.url else { return c.error }
        keystore.localURL = url.absoluteString
        if !c.loopback { keystore.localRemoteApproved = approveRemote ? url.absoluteString : nil }
        return nil
    }

    public func localIsRemote() -> Bool {
        let c = LocalServer.validate(localAddress)
        return c.url != nil && !c.loopback
    }

    public func localModels() async -> (models: [String], error: String?) {
        let t = localTarget()
        guard let url = t.url else { return ([], t.error) }
        return await api.localModels(base: url, apiKey: keystore.key(ProviderID.local.rawValue))
    }

    func askLocal(question: String, snapshot: SnapshotInput, token: CancelToken, test: Bool) async -> AgentAnswer {
        let model = currentModel(.local)
        let t = localTarget()
        guard let url = t.url else { return .failure(t.error ?? "The local server address is not valid.", model: model) }
        let key = keystore.key(ProviderID.local.rawValue)
        // Local models are often loaded with a small context window, so they get the short snapshot.
        var text = test ? "Reply with OK" : PromptBuilder.compactMessage(question: question, snapshot: snapshot)
        let suffix = keystore.localSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !suffix.isEmpty { text += " \(suffix)" }
        let system = test ? "You are a connectivity check." : Prompt.system
        return await withDeadline(token, model: model, id: .local, seconds: LocalServer.deadline) { [api] in
            await api.askLocal(base: url, apiKey: key, model: model, system: system, userText: text, allowEmpty: test, maxTokens: test ? 512 : LocalServer.maxOutputTokens)
        }
    }
}
