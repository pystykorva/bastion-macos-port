import XCTest
@testable import TessuCore

func jsonObj(_ s: String) -> [String: Any] { try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any] }

final class LocalServerTests: XCTestCase {
    func testAddressNormalisation() {
        XCTAssertEqual(LocalServer.validate("localhost:1234").url?.absoluteString, "http://localhost:1234/v1")
        XCTAssertEqual(LocalServer.validate("http://127.0.0.1:1235/v1/").url?.absoluteString, "http://127.0.0.1:1235/v1")
        XCTAssertEqual(LocalServer.validate("http://localhost:1234/v1/chat/completions").url?.absoluteString, "http://localhost:1234/v1")
        XCTAssertEqual(LocalServer.validate("http://localhost:11434").url?.absoluteString, "http://localhost:11434/v1", "a bare host gets /v1")
        XCTAssertEqual(LocalServer.validate("https://gpu.lan:8443/openai/v1").url?.absoluteString, "https://gpu.lan:8443/openai/v1")
    }

    func testBadAddressesAreRefusedWithAReason() {
        for bad in ["", "   ", "ftp://x", "http://", "not a url at all"] {
            XCTAssertNil(LocalServer.validate(bad).url, bad)
            XCTAssertNotNil(LocalServer.validate(bad).error, bad)
        }
        XCTAssertTrue(LocalServer.validate("http://user:pw@localhost:1234").error?.contains("key field") == true, "no secrets in the address")
    }

    func testLoopbackDetection() {
        for h in ["localhost:1234", "127.0.0.1:1235", "http://[::1]:8080", "http://127.5.5.5", "http://app.localhost:1"] {
            XCTAssertTrue(LocalServer.validate(h).loopback, h)
        }
        for h in ["http://192.168.1.50:1234", "http://gpu.lan:1234", "https://example.com", "http://localhost.evil.com"] {
            XCTAssertFalse(LocalServer.validate(h).loopback, h)
        }
    }

    func testModelListSkipsEmbeddingsAndDuplicates() {
        let json = jsonObj(#"{"data":[{"id":"qwen3.8-27b"},{"id":"text-embedding-nomic-embed-text-v1.5"},{"id":"qwen3.8-27b"},{"id":"bge-reranker"},{"id":"llama-4-scout","type":"llm"},{"id":"x","type":"embeddings"}]}"#)
        XCTAssertEqual(LocalServer.parseModels(json), ["qwen3.8-27b", "llama-4-scout"])
        XCTAssertEqual(LocalServer.parseModels(jsonObj(#"{"models":[{"name":"llama3:8b"}]}"#)), ["llama3:8b"], "Ollama's native shape")
        XCTAssertEqual(LocalServer.parseModels(jsonObj("{}")), [])
    }

    func testRemoteServerNeedsExplicitApproval() {
        let a = Agents(keystore: Keystore(defaults: UserDefaults(suiteName: "bt.\(UUID().uuidString)")!, inMemory: true),
                       api: ApiProviders(), cli: CLIRunner(baseDir: FileManager.default.temporaryDirectory.appendingPathComponent("bt-\(UUID().uuidString)")))
        XCTAssertNil(a.setLocalAddress("http://localhost:1235/v1"))
        XCTAssertNotNil(a.localTarget().url, "this Mac needs no approval")
        XCTAssertNil(a.setLocalAddress("http://192.168.1.50:1234/v1"))
        XCTAssertNil(a.localTarget().url, "a LAN machine is blocked until approved")
        XCTAssertTrue(a.localTarget().error?.contains("not on this Mac") == true)
        XCTAssertNil(a.setLocalAddress("http://192.168.1.50:1234/v1", approveRemote: true))
        XCTAssertNotNil(a.localTarget().url)
        XCTAssertNil(a.setLocalAddress("http://192.168.1.99:1234/v1"), "a different address needs a new approval")
        XCTAssertNil(a.localTarget().url)
    }
}
