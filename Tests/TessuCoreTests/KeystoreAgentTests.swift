import XCTest
@testable import TessuCore

final class KeystoreAgentTests: XCTestCase {
    private func agents() -> Agents {
        let defaults = UserDefaults(suiteName: "tessu.test.\(UUID().uuidString)")!
        return Agents(keystore: Keystore(defaults: defaults, inMemory: true), api: ApiProviders(), cli: CLIRunner(baseDir: FileManager.default.temporaryDirectory.appendingPathComponent("bt-\(UUID().uuidString)")))
    }

    func testKeyValidation() {
        let a = agents()
        XCTAssertEqual(a.setKey(.claude, ""), "Paste an API key first.")
        XCTAssertNotNil(a.setKey(.openai, "short"))
        XCTAssertNotNil(a.setKey(.openai, "sk-has spaces inside it 1234567890"))
        XCTAssertTrue(a.setKey(.claude, "sk-openai-wrong-prefix-1234567890")?.contains("sk-ant-") == true)
        XCTAssertNotNil(a.setKey(.claudeCli, "sk-ant-whatever-whatever-1234567"), "a subscription takes no key")
        XCTAssertNil(a.setKey(.claude, "  sk-ant-api03-abcdefghijklmnopqrstuv  "), "surrounding whitespace is trimmed")
        XCTAssertEqual(a.keystore.key("claude"), "sk-ant-api03-abcdefghijklmnopqrstuv")
    }

    func testKeyLifecycleAndProviderList() async {
        let a = agents()
        XCTAssertFalse(a.keystore.hasKey("grok"))
        XCTAssertNil(a.setKey(.grok, "xai-abcdefghijklmnopqrstuvwxyz"))
        let list = await a.providers()
        XCTAssertEqual(list.first { $0.id == .grok }?.hasKey, true)
        XCTAssertEqual(list.first { $0.id == .openai }?.hasKey, false)
        XCTAssertEqual(list.count, ProviderID.allCases.count)
        XCTAssertNil(a.clearKey(.grok))
        XCTAssertFalse(a.keystore.hasKey("grok"))
    }

    func testModelChoice() {
        let a = agents()
        XCTAssertEqual(a.currentModel(.openai), "gpt-5")
        XCTAssertNil(a.setModel(.openai, "gpt-5-mini"))
        XCTAssertEqual(a.currentModel(.openai), "gpt-5-mini")
        XCTAssertNotNil(a.setModel(.openai, "bad model; rm -rf /"))
        XCTAssertNotNil(a.setModel(.claude, "gpt-5"), "Claude names start with claude-")
        XCTAssertNil(a.setModel(.claudeCli, "opus"))
    }

    func testAskWithoutKeyOrQuestionExplainsInsteadOfThrowing() async {
        let a = agents()
        let none = await a.ask(.openai, question: "hi", snapshot: SnapshotInput())
        XCTAssertFalse(none.ok); XCTAssertTrue(none.error?.contains("No API key saved") == true)
        _ = a.setKey(.openai, "sk-abcdefghijklmnopqrstuvwxyz")
        let empty = await a.ask(.openai, question: "   ", snapshot: SnapshotInput())
        XCTAssertEqual(empty.error, "Type a question first.")
    }

    func testPreviewIsExactlyWhatIsSent() {
        let a = agents()
        let p = a.preview(PrivacyFixture.snapshot())
        XCTAssertFalse(p.snapshot.contains(PrivacyFixture.ssid))
        XCTAssertEqual(p.system, Prompt.system)
        XCTAssertTrue(p.snapshot.contains("\"privacy\""))
    }

    func testModelPatternRejectsShellAndFlagLookalikes() {
        for bad in ["--tools", "a b", "a;b", "$(x)", "", "-m", "a\nb"] { XCTAssertFalse(CLILocator.isValidModel(bad), bad) }
        for good in ["opus", "claude-opus-5-5", "gpt-5", "o3:high", "provider/model-1.2"] { XCTAssertTrue(CLILocator.isValidModel(good), good) }
    }
}
