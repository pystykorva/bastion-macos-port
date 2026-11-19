import Foundation
import Security

/// API keys for AI providers, kept in the macOS Keychain (the native counterpart of the original's
/// Electron safeStorage). A key is only ever read inside the engine, right before a request. It is never
/// returned to the UI and never logged. The chosen model per provider is not secret and lives in UserDefaults.
public final class Keystore: @unchecked Sendable {
    public static let shared = Keystore()

    private let service: String
    private let defaults: UserDefaults
    /// nil = the real Keychain. Tests inject an in-memory store.
    private let memory: MemoryBox?

    public init(service: String = "com.pystykorva.tessu.apikeys", defaults: UserDefaults = .standard, inMemory: Bool = false) {
        self.service = service
        self.defaults = defaults
        self.memory = inMemory ? MemoryBox() : nil
    }

    final class MemoryBox: @unchecked Sendable {
        let lock = NSLock()
        var items: [String: String] = [:]
    }

    public enum KeyError: Error, LocalizedError {
        case keychain(OSStatus)
        public var errorDescription: String? {
            switch self {
            case .keychain(let s):
                let text = SecCopyErrorMessageString(s, nil) as String? ?? "status \(s)"
                return "The macOS Keychain refused the request (\(text))."
            }
        }
    }

    private func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id]
    }

    // MARK: keys

    public func setKey(_ id: String, _ key: String) throws {
        if let m = memory { m.lock.lock(); m.items[id] = key; m.lock.unlock(); return }
        let data = Data(key.utf8)
        var add = query(id)
        add[kSecValueData as String] = data
        // Only readable while this Mac is unlocked, and never copied to other devices.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw KeyError.keychain(status) }
    }

    /// The decrypted key or nil. Engine use only.
    public func key(_ id: String) -> String? {
        if let m = memory { m.lock.lock(); defer { m.lock.unlock() }; return m.items[id] }
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        let s = String(decoding: data, as: UTF8.self)
        return s.isEmpty ? nil : s
    }

    /// Presence only: does not read the secret, so it never triggers a Keychain prompt.
    public func hasKey(_ id: String) -> Bool {
        if let m = memory { m.lock.lock(); defer { m.lock.unlock() }; return m.items[id] != nil }
        var q = query(id)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    public func clearKey(_ id: String) throws {
        if let m = memory { m.lock.lock(); m.items[id] = nil; m.lock.unlock(); return }
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError.keychain(status) }
    }

    // MARK: local server (address is not secret; an optional key is kept in the Keychain as provider "local")

    public var localURL: String? {
        get { let s = defaults.string(forKey: "tessu.local.url"); return (s?.isEmpty == false) ? s : nil }
        set { defaults.set(newValue, forKey: "tessu.local.url") }
    }

    /// The address the user explicitly allowed to be a non-loopback one (a question leaves this Mac for it).
    public var localRemoteApproved: String? {
        get { defaults.string(forKey: "tessu.local.remoteOK") }
        set { defaults.set(newValue, forKey: "tessu.local.remoteOK") }
    }

    /// Text appended to every question for the local server, for example "/no_think" for Qwen models.
    public var localSuffix: String {
        get { defaults.string(forKey: "tessu.local.suffix") ?? "" }
        set { defaults.set(String(newValue.prefix(120)), forKey: "tessu.local.suffix") }
    }

    // MARK: model choice

    private func modelKey(_ id: String) -> String { "tessu.model.\(id)" }

    public func model(_ id: String) -> String? {
        let m = defaults.string(forKey: modelKey(id))
        return (m?.isEmpty == false) ? m : nil
    }

    public func setModel(_ id: String, _ model: String) { defaults.set(model, forKey: modelKey(id)) }
}
