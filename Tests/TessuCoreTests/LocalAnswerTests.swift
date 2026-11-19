import XCTest
@testable import TessuCore

final class LocalAnswerTests: XCTestCase {
    func testReasoningTokensAreNotPartOfTheAnswer() {
        let ok = ApiProviders.parseLocal(jsonObj(#"{"model":"qwen","choices":[{"finish_reason":"stop","message":{"content":"\n\nOK","reasoning_content":"thinking..."}}]}"#), model: "m", allowEmpty: false)
        XCTAssertTrue(ok.ok); XCTAssertEqual(ok.text, "OK")
        let inline = ApiProviders.parseLocal(jsonObj(#"{"choices":[{"message":{"content":"<think>step 1\nstep 2</think>\nFix DNS first."}}]}"#), model: "m", allowEmpty: false)
        XCTAssertEqual(inline.text, "Fix DNS first.")
        XCTAssertEqual(LocalServer.stripThinking("a<think>x</think>b<think>y</think>c"), "abc")
    }

    func testModelThatOnlyThoughtGetsAnExplanation() {
        let r = ApiProviders.parseLocal(jsonObj(#"{"model":"qwen","choices":[{"finish_reason":"length","message":{"content":"","reasoning_content":"long thinking"}}]}"#), model: "m", allowEmpty: false)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.error?.contains("thinking") == true)
        let plain = ApiProviders.parseLocal(jsonObj(#"{"choices":[{"message":{"content":""}}]}"#), model: "m", allowEmpty: false)
        XCTAssertEqual(plain.error, "The local model returned an empty answer.")
    }

    func testFailureSentences() {
        func f(_ status: Int, _ body: String) -> String {
            ApiProviders.localFailure(status: status, reply: .init(status: status, json: jsonObj(body), body: body), key: nil)
        }
        XCTAssertTrue(f(400, #"{"error":{"message":"No models loaded. Please load a model."}}"#).contains("no model loaded"))
        XCTAssertTrue(f(400, #"{"error":{"message":"Trying to keep 9000 tokens but context length exceeded 4096"}}"#).contains("context window"))
        XCTAssertTrue(f(401, "{}").contains("rejected the key"))
        XCTAssertTrue(f(404, "{}").contains("/v1"))
        XCTAssertTrue(LocalServer.unreachable(URL(string: "http://localhost:1234/v1")!).contains("1234"))
    }

    func testCompactSnapshotIsSmallerAndStillPrivate() {
        var s = PrivacyFixture.snapshot()
        s.devices = (0..<40).map { Device(ip: "10.0.0.\($0)", mac: "aa:bb:cc:dd:ee:ff", vendor: "Apple", randomizedMac: false, isGateway: false, isThisComputer: false, hostname: nil) }
        s.connections = (0..<200).map { Connection(process: "p\($0)", pid: $0, proto: "tcp", local: "1.1.1.1:1", remoteIp: "8.8.8.\($0 % 250)", remotePort: 443, state: "ESTABLISHED") }
        let full = PromptBuilder.minimizeSnapshot(s).serialized()
        let compact = PromptBuilder.compactSnapshot(s).serialized()
        XCTAssertLessThan(compact.count, full.count / 2)
        for secret in [PrivacyFixture.ssid, PrivacyFixture.host, PrivacyFixture.mac, PrivacyFixture.publicIp, "NeighbourNet-9000", "Lev's-iPhone"] {
            XCTAssertFalse(compact.localizedCaseInsensitiveContains(secret), "leaked: \(secret)")
        }
        XCTAssertTrue(compact.contains("\"id\":\"location-map\""), "the findings survive")
        XCTAssertTrue(compact.contains("\"connections\":null"), "the connection list is dropped")
    }
}
