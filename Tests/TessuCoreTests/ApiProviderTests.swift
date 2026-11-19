import XCTest
@testable import TessuCore

final class ApiProviderTests: XCTestCase {
    private func obj(_ s: String) -> [String: Any] { try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any] }

    func testClaudeText() {
        let r = ApiProviders.parseClaude(obj(#"{"model":"claude-opus-5-5","stop_reason":"end_turn","content":[{"type":"text","text":"Hello"},{"type":"thinking","thinking":"x"},{"type":"text","text":"World"}]}"#), model: "m", allowEmpty: false)
        XCTAssertTrue(r.ok); XCTAssertEqual(r.text, "Hello\n\nWorld"); XCTAssertEqual(r.model, "claude-opus-5-5")
    }

    func testClaudeRefusalAndTruncationAndEmpty() {
        let ref = ApiProviders.parseClaude(obj(#"{"stop_reason":"refusal","stop_details":{"category":"cyber","explanation":"no"},"content":[]}"#), model: "m", allowEmpty: false)
        XCTAssertFalse(ref.ok); XCTAssertTrue(ref.error?.contains("declined") == true); XCTAssertTrue(ref.error?.contains("cyber") == true)
        let cut = ApiProviders.parseClaude(obj(#"{"stop_reason":"max_tokens","content":[{"type":"text","text":"Partial"}]}"#), model: "m", allowEmpty: false)
        XCTAssertTrue(cut.ok); XCTAssertTrue(cut.text.contains("cut off"))
        XCTAssertFalse(ApiProviders.parseClaude(obj(#"{"content":[]}"#), model: "m", allowEmpty: false).ok)
        XCTAssertTrue(ApiProviders.parseClaude(obj(#"{"content":[]}"#), model: "m", allowEmpty: true).ok, "a connectivity test accepts an empty answer")
    }

    func testOpenAIReadsOutputTextParts() {
        let json = #"{"model":"gpt-5","status":"completed","output":[{"type":"reasoning","content":[]},{"type":"message","content":[{"type":"output_text","text":"Answer"}]}]}"#
        let r = ApiProviders.parseOpenAI(obj(json), model: "m", allowEmpty: false)
        XCTAssertTrue(r.ok); XCTAssertEqual(r.text, "Answer")
    }

    func testOpenAIRefusalIncompleteAndError() {
        let ref = ApiProviders.parseOpenAI(obj(#"{"output":[{"content":[{"type":"refusal","refusal":"can't"}]}]}"#), model: "m", allowEmpty: false)
        XCTAssertFalse(ref.ok); XCTAssertTrue(ref.error?.contains("declined") == true)
        let inc = ApiProviders.parseOpenAI(obj(#"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[{"content":[{"type":"output_text","text":"Some"}]}]}"#), model: "m", allowEmpty: false)
        XCTAssertTrue(inc.ok); XCTAssertTrue(inc.text.contains("max_output_tokens"))
        XCTAssertFalse(ApiProviders.parseOpenAI(obj(#"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}"#), model: "m", allowEmpty: false).ok)
        XCTAssertTrue(ApiProviders.parseOpenAI(obj(#"{"status":"incomplete","output":[]}"#), model: "m", allowEmpty: true).ok, "test: a completed call proves the key")
        XCTAssertFalse(ApiProviders.parseOpenAI(obj(#"{"error":{"message":"boom sk-abcdefghijklmnop"}}"#), model: "m", allowEmpty: true).ok)
        let err = ApiProviders.parseOpenAI(obj(#"{"error":{"message":"bad key sk-abcdefghijklmnop"}}"#), model: "m", allowEmpty: true)
        XCTAssertFalse(err.error?.contains("sk-abcdefghijklmnop") == true, "keys are scrubbed from messages")
    }

    func testGrok() {
        let ok = ApiProviders.parseGrok(obj(#"{"model":"grok-4","choices":[{"finish_reason":"stop","message":{"content":" Hi "}}]}"#), model: "m", allowEmpty: false)
        XCTAssertTrue(ok.ok); XCTAssertEqual(ok.text, "Hi")
        let cut = ApiProviders.parseGrok(obj(#"{"choices":[{"finish_reason":"length","message":{"content":"Part"}}]}"#), model: "m", allowEmpty: false)
        XCTAssertTrue(cut.text.contains("cut off"))
        XCTAssertFalse(ApiProviders.parseGrok(obj(#"{"choices":[{"message":{"refusal":"no"}}]}"#), model: "m", allowEmpty: false).ok)
        XCTAssertFalse(ApiProviders.parseGrok(obj(#"{"choices":[]}"#), model: "m", allowEmpty: false).ok)
    }

    func testErrorSentences() {
        func d(_ status: Int, _ body: String = "{}") -> String {
            ApiClient.describe(status: status, reply: .init(status: status, json: obj(body), body: body), error: nil, vendor: "Anthropic", key: "sk-ant-secretsecretsecret1")
        }
        XCTAssertTrue(d(401).contains("rejected")); XCTAssertTrue(d(404).contains("model was not found")); XCTAssertTrue(d(429).contains("rate limit"))
        XCTAssertTrue(d(400, #"{"error":{"message":"bad sk-ant-secretsecretsecret1 param"}}"#).contains("[key]"))
        XCTAssertFalse(d(400, #"{"error":{"message":"bad sk-ant-secretsecretsecret1 param"}}"#).contains("secretsecret"))
        XCTAssertTrue(ApiClient.describe(status: 0, reply: nil, error: URLError(.timedOut), vendor: "xAI", key: nil).contains("timed out"))
        XCTAssertTrue(ApiClient.describe(status: 0, reply: nil, error: URLError(.notConnectedToInternet), vendor: "xAI", key: nil).contains("Could not reach xAI"))
    }

    func testScrub() {
        XCTAssertEqual(ApiClient.scrub("key=abc123456789 here", key: "abc123456789"), "key=[key] here")
        XCTAssertEqual(ApiClient.scrub("xai-abcdefghijk and sk-proj-abcdefgh", key: nil), "[key] and [key]")
        XCTAssertEqual(ApiClient.scrub(String(repeating: "x", count: 900), key: nil).count, 400)
    }
}
