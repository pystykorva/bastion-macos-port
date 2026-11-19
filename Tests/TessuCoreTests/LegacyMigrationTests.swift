import XCTest
@testable import TessuCore

final class LegacyMigrationTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "tessu.test.\(UUID().uuidString)")! }

    func testKeysAreRenamedAndLayoutKeysAreLeftBehind() {
        XCTAssertEqual(LegacyMigration.newKey("bastion.model.openrouter"), "tessu.model.openrouter")
        XCTAssertEqual(LegacyMigration.newKey("bastion.local.url"), "tessu.local.url")
        XCTAssertEqual(LegacyMigration.newKey("agentProvider"), "agentProvider", "plain keys keep their name")
        XCTAssertFalse(LegacyMigration.isCopyable("NSWindow Frame SwiftUI.WindowGroup<Bastion.RootView>-1-AppWindow-1"))
        XCTAssertFalse(LegacyMigration.isCopyable("NSSplitView Subview Frames x"))
        XCTAssertFalse(LegacyMigration.isCopyable("AppleLanguages"))
        XCTAssertTrue(LegacyMigration.isCopyable("advancedEvidence"))
    }

    func testSettingsAreCopiedButNeverOverwriteNewOnes() {
        let d = defaults()
        d.set("claude", forKey: "agentProvider") // already chosen in the new app
        let old: [String: Any] = ["agentProvider": "openrouter", "advancedEvidence": true, "watchMinutes": 30,
                                  "bastion.model.openrouter": "openrouter/auto", "NSWindow Frame foo": "1 2 3 4"]
        XCTAssertEqual(LegacyMigration.migrateDefaults(from: old, into: d), 3)
        XCTAssertEqual(d.string(forKey: "agentProvider"), "claude", "the user's newer choice wins")
        XCTAssertEqual(d.bool(forKey: "advancedEvidence"), true)
        XCTAssertEqual(d.integer(forKey: "watchMinutes"), 30)
        XCTAssertEqual(d.string(forKey: "tessu.model.openrouter"), "openrouter/auto")
        XCTAssertNil(d.object(forKey: "NSWindow Frame foo"))
        XCTAssertNil(d.object(forKey: "bastion.model.openrouter"), "no old-named key is written")
    }

    func testHistoryFilesAreCopiedNotMovedAndNotOverwritten() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("tessu-mig-\(UUID().uuidString)")
        let old = root.appendingPathComponent("Bastion"), new = root.appendingPathComponent("Tessu")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("old chat".utf8).write(to: old.appendingPathComponent("agent-log.json"))
        try Data("old speed".utf8).write(to: old.appendingPathComponent("speed-history.json"))
        try Data("not json".utf8).write(to: old.appendingPathComponent("notes.txt"))
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("new speed".utf8).write(to: new.appendingPathComponent("speed-history.json"))
        defer { try? fm.removeItem(at: root) }

        XCTAssertEqual(LegacyMigration.migrateFiles(from: old, to: new), 1)
        XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("agent-log.json")), "old chat")
        XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("speed-history.json")), "new speed", "existing file kept")
        XCTAssertFalse(fm.fileExists(atPath: new.appendingPathComponent("notes.txt").path), "only .json files")
        XCTAssertTrue(fm.fileExists(atPath: old.appendingPathComponent("agent-log.json").path), "the old data stays")
    }

    func testMissingOldFolderIsNotAnError() {
        let none = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        XCTAssertEqual(LegacyMigration.migrateFiles(from: none, to: none.appendingPathExtension("new")), 0)
    }

    func testRunsOnlyOnce() {
        let d = defaults()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tessu-once-\(UUID().uuidString)/Tessu")
        let ks = Keystore(defaults: d, inMemory: true)
        let first = LegacyMigration.runIfNeeded(defaults: d, keystore: ks, newSupportDir: dir, keys: false)
        XCTAssertFalse(first.skipped)
        XCTAssertTrue(LegacyMigration.runIfNeeded(defaults: d, keystore: ks, newSupportDir: dir, keys: false).skipped)
    }
}
