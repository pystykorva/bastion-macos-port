import Foundation

/// Provider registry, key storage and the ask / test entry points used by the app. Every function
/// resolves with data and never throws; failures come back as plain sentences.
public final class Agents: @unchecked Sendable {
    public static let shared = Agents()

    /// Overall limit for one ask, retries included, so a hung request can never hold a provider's lock
    /// (watch mode included) for long.
    public static let deadline: TimeInterval = 4 * 60

    public let keystore: Keystore
    let api: ApiProviders
    let cli: CLIRunner
    private let lock = NSLock()
    private var running: [ProviderID: CancelToken] = [:]

    public init(keystore: Keystore = .shared, api: ApiProviders = ApiProviders(), cli: CLIRunner = .shared) {
        self.keystore = keystore; self.api = api; self.cli = cli
    }

    // MARK: providers

    public func currentModel(_ id: ProviderID) -> String { keystore.model(id.rawValue) ?? id.defaultModel }

    /// For a CLI, `hasKey` means "installed and usable" (signed in, or not known to be signed out).
    public func providers(refresh: Bool = false) async -> [ProviderInfo] {
        var out: [ProviderInfo] = []
        for id in ProviderID.allCases {
            let model = currentModel(id)
            var models = id.knownModels
            if !models.contains(model) { models.append(model) }
            if id.isCLI {
                let st = await cli.status(id, force: refresh)
                var c = CLIStatus()
                c = st
                out.append(ProviderInfo(id: id, hasKey: st.installed && st.loggedIn != false, model: model, models: models, cli: c))
            } else {
                out.append(ProviderInfo(id: id, hasKey: id == .local ? keystore.localURL != nil : keystore.hasKey(id.rawValue), model: model, models: models, cli: nil))
            }
        }
        return out
    }

    // MARK: keys and models

    public func validateKey(_ id: ProviderID, _ key: String) -> String? {
        if id.isCLI { return "\(id.name) uses your \(CLILocator.spec(id)?.product ?? "CLI") login, not an API key." }
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { return "Paste an API key first." }
        // Local servers take no key or any short token the user chose, so only the basics apply.
        if id == .local { return k.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.value < 0x20 }) || k.count > 512 ? "That does not look like a key. Copy it without spaces." : nil }
        if k.count < 20 || k.count > 512 || k.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.value < 0x20 || $0.value == 0x7f }) {
            return "That does not look like an API key. Copy the whole key without spaces."
        }
        if id == .claude && !k.hasPrefix("sk-ant-") {
            return "Anthropic API keys start with \"sk-ant-\". Create one in the Claude Console under API keys."
        }
        if id == .openrouter && !k.hasPrefix("sk-or-") {
            return "OpenRouter API keys start with \"sk-or-\". Create one at openrouter.ai/keys."
        }
        return nil
    }

    /// nil = saved, otherwise the plain-sentence reason it was not.
    public func setKey(_ id: ProviderID, _ key: String) -> String? {
        if let problem = validateKey(id, key) { return problem }
        do { try keystore.setKey(id.rawValue, key.trimmingCharacters(in: .whitespacesAndNewlines)); return nil }
        catch { return "Could not save the key: \(errMsg(error))" }
    }

    public func clearKey(_ id: ProviderID) -> String? {
        if id.isCLI { return "\(id.name) has no API key. Sign out with \(CLILocator.spec(id)?.product ?? "the CLI") itself." }
        do { try keystore.clearKey(id.rawValue); return nil } catch { return "Could not remove the key: \(errMsg(error))" }
    }

    /// Any well-formed model id is accepted (custom models); the provider decides whether it exists,
    /// and a test reports that.
    public func setModel(_ id: ProviderID, _ model: String) -> String? {
        let m = model.trimmingCharacters(in: .whitespaces)
        guard Rx.test("^[A-Za-z0-9][A-Za-z0-9._:/-]{0,99}$", m), !id.isCLI || CLILocator.isValidModel(m) else { return "Invalid model name." }
        if id == .claude && !m.hasPrefix("claude-") { return "Claude model names start with \"claude-\"." }
        keystore.setModel(id.rawValue, m)
        return nil
    }

    // MARK: asking

    func begin(_ id: ProviderID) -> CancelToken? {
        lock.lock(); defer { lock.unlock() }
        if running[id] != nil { return nil }
        let t = CancelToken()
        running[id] = t
        return t
    }

    func end(_ id: ProviderID, _ t: CancelToken) {
        lock.lock(); if running[id] === t { running[id] = nil }; lock.unlock()
    }

    public func isBusy(_ id: ProviderID) -> Bool { lock.lock(); defer { lock.unlock() }; return running[id] != nil }

    /// Stops a running ask or test for this provider; it resolves with "Cancelled.".
    public func cancel(_ id: ProviderID) {
        lock.lock(); let t = running[id]; lock.unlock()
        t?.cancel()
    }

    /// App quit: cancel every request and kill every CLI still running.
    public func shutdown() {
        lock.lock(); let all = Array(running.values); lock.unlock()
        all.forEach { $0.cancel() }
        cli.killAll()
    }

    func keyOrReason(_ id: ProviderID) -> (key: String?, error: String?) {
        guard keystore.hasKey(id.rawValue) else {
            return (nil, "No API key saved for \(id.name). Add your \(id.vendor) key in Settings.")
        }
        guard let k = keystore.key(id.rawValue) else {
            return (nil, "The saved \(id.name) key could not be read from the Keychain. Remove it and add it again.")
        }
        return (k, nil)
    }
}
