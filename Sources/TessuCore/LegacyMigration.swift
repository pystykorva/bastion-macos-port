import Foundation
import Security

/// One-time copy of the data the app kept while it was still called Bastion: settings, chat and speed
/// history, and API keys. It only copies. The old data is left in place, so nothing can be lost, and the
/// user can remove it whenever they like. Runs once (a flag is stored), before any screen reads its settings.
public enum LegacyMigration {
    public static let oldBundleID = "app.bastion.desktop"
    public static let oldKeychainService = "app.bastion.desktop.apikeys"
    public static let oldSupportFolder = "Bastion"
    static let doneKey = "tessu.migratedFromBastion"

    /// Window-layout keys embed the old Swift module names, so they are not worth carrying over.
    static func isCopyable(_ key: String) -> Bool {
        !key.hasPrefix("NS") && !key.hasPrefix("Apple") && !key.hasPrefix("com.apple") && !key.contains("WindowGroup")
    }

    /// "bastion.model.openrouter" becomes "tessu.model.openrouter"; plain keys keep their name.
    static func newKey(_ old: String) -> String {
        old.hasPrefix("bastion.") ? "tessu." + old.dropFirst("bastion.".count) : old
    }

    /// Copies settings the new domain does not have yet. Returns how many were copied.
    @discardableResult
    static func migrateDefaults(from old: [String: Any], into defaults: UserDefaults) -> Int {
        var n = 0
        for (key, value) in old where isCopyable(key) {
            let target = newKey(key)
            guard defaults.object(forKey: target) == nil else { continue }
            defaults.set(value, forKey: target)
            n += 1
        }
        return n
    }

    /// Copies the chat and speed history files, never overwriting a file that already exists.
    @discardableResult
    static func migrateFiles(from oldDir: URL, to newDir: URL, fm: FileManager = .default) -> Int {
        guard let names = try? fm.contentsOfDirectory(atPath: oldDir.path) else { return 0 }
        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        var n = 0
        for name in names where name.hasSuffix(".json") {
            let to = newDir.appendingPathComponent(name)
            if fm.fileExists(atPath: to.path) { continue }
            if (try? fm.copyItem(at: oldDir.appendingPathComponent(name), to: to)) != nil { n += 1 }
        }
        return n
    }

    /// Copies every API key from the old Keychain service to the new one. Reading an item made by the old
    /// build may show macOS's one-time "allow access" prompt, and the user can decline it.
    @discardableResult
    static func migrateKeys(fromService old: String, to keystore: Keystore) -> Int {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: old,
                                kSecReturnAttributes as String: true, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitAll]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return 0 }
        var n = 0
        for item in items {
            guard let id = item[kSecAttrAccount as String] as? String, let data = item[kSecValueData as String] as? Data,
                  let key = String(data: data, encoding: .utf8), !key.isEmpty, !keystore.hasKey(id) else { continue }
            if (try? keystore.setKey(id, key)) != nil { n += 1 }
        }
        return n
    }

    public struct Result: Sendable { public var settings = 0, files = 0, keys = 0, skipped = false }

    /// The real run. `keys` can be switched off for tests and for unattended runs (a prompt would block).
    @discardableResult
    public static func runIfNeeded(defaults: UserDefaults = .standard, keystore: Keystore = .shared,
                                   newSupportDir: URL, keys: Bool = true) -> Result {
        var r = Result()
        guard !defaults.bool(forKey: doneKey) else { r.skipped = true; return r }
        defaults.set(true, forKey: doneKey) // set first: a crash or a declined prompt must not repeat itself on every launch
        if let old = UserDefaults.standard.persistentDomain(forName: oldBundleID) { r.settings = migrateDefaults(from: old, into: defaults) }
        let oldDir = newSupportDir.deletingLastPathComponent().appendingPathComponent(oldSupportFolder, isDirectory: true)
        r.files = migrateFiles(from: oldDir, to: newSupportDir)
        if keys { r.keys = migrateKeys(fromService: oldKeychainService, to: keystore) }
        return r
    }
}
