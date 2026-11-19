import XCTest
@testable import TessuCore

final class OpenRouterTests: XCTestCase {
    private func obj(_ s: String) -> [String: Any] { try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any] }

    func testProviderBasics() {
        XCTAssertEqual(ProviderID.openrouter.name, "OpenRouter")
        XCTAssertEqual(ProviderID.openrouter.tab, "OpenRouter")
        XCTAssertFalse(ProviderID.openrouter.isCLI)
        XCTAssertEqual(ProviderID.openrouter.defaultModel, "openrouter/auto")
        XCTAssertNotNil(ProviderID.openrouter.keyPage)
        XCTAssertTrue(ProviderID.allCases.contains(.openrouter))
    }

    func testParsesChatCompletionsAndNamesTheProvider() {
        let ok = ApiProviders.parseGrok(obj(#"{"model":"anthropic/claude-sonnet","choices":[{"finish_reason":"stop","message":{"content":" Hi "}}]}"#),
                                        model: "openrouter/auto", allowEmpty: false, name: "OpenRouter")
        XCTAssertTrue(ok.ok); XCTAssertEqual(ok.text, "Hi")
        XCTAssertEqual(ok.model, "anthropic/claude-sonnet", "shows which model OpenRouter actually routed to")
        let empty = ApiProviders.parseGrok(obj(#"{"choices":[]}"#), model: "m", allowEmpty: false, name: "OpenRouter")
        XCTAssertEqual(empty.error, "OpenRouter returned an empty answer.")
    }

    func testKeyRulesAndCustomModelIds() {
        let a = Agents(keystore: Keystore(defaults: UserDefaults(suiteName: "bt.\(UUID().uuidString)")!, inMemory: true),
                       api: ApiProviders(), cli: CLIRunner(baseDir: FileManager.default.temporaryDirectory.appendingPathComponent("bt-\(UUID().uuidString)")))
        XCTAssertTrue(a.setKey(.openrouter, "sk-ant-wrong-prefix-abcdefghijkl")?.contains("sk-or-") == true)
        XCTAssertNil(a.setKey(.openrouter, "sk-or-v1-abcdefghijklmnopqrstuvwxyz"))
        XCTAssertNil(a.setModel(.openrouter, "anthropic/claude-sonnet-4.5"), "vendor/model ids are valid")
        XCTAssertNil(a.setModel(.openrouter, "meta-llama/llama-3.3-70b-instruct:free"))
        XCTAssertEqual(a.currentModel(.openrouter), "meta-llama/llama-3.3-70b-instruct:free")
    }

    func testKeyIsScrubbedFromErrors() {
        XCTAssertEqual(ApiClient.scrub("bad key sk-or-v1-abcdef123456 here", key: nil), "bad key [key] here")
    }
}
