import XCTest
@testable import TessuCore

final class FeedbackConfigTests: XCTestCase {
    func testEmptyOrTemplateConfigHasNoDestination() {
        for info in [nil, [:], ["TessuFeedbackEmail": "", "TessuFeedbackIssuesURL": ""],
                     ["TessuFeedbackEmail": "__FEEDBACK_EMAIL__", "TessuFeedbackIssuesURL": "__FEEDBACK_ISSUES_URL__"]] as [[String: Any]?] {
            let c = FeedbackConfig(info: info)
            XCTAssertFalse(c.isConfigured)
            XCTAssertNil(c.email); XCTAssertNil(c.issuesURL)
            XCTAssertNil(c.mailto(subject: "s", body: "b"))
            XCTAssertNil(c.issue(title: "t", body: "b"))
            XCTAssertTrue(c.destination.contains("no feedback address"))
        }
    }

    func testSourceTreeContainsNoDestination() throws {
        // The guarantee behind the feature: nothing in the sources or the plist template names a real inbox.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fm = FileManager.default
        var checked = 0
        for dir in ["Sources", "Resources"] {
            let it = fm.enumerator(at: root.appendingPathComponent(dir), includingPropertiesForKeys: nil)
            while let u = it?.nextObject() as? URL {
                guard ["swift", "plist"].contains(u.pathExtension) else { continue }
                let text = try String(contentsOf: u, encoding: .utf8)
                checked += 1
                XCTAssertNil(Rx.first("[A-Za-z0-9._%+-]+@(?!example\\.com)[A-Za-z0-9-]+\\.[A-Za-z]{2,}", in: text), "email address in \(u.lastPathComponent)")
                XCTAssertFalse(text.contains("beyond-media"), u.lastPathComponent)
                XCTAssertFalse(text.contains("github.com/0xCodez/bastion/issues"), "tracker URL hard-coded in \(u.lastPathComponent)")
            }
        }
        XCTAssertGreaterThan(checked, 50)
    }

    func testValidConfigIsRead() {
        let c = FeedbackConfig(info: ["TessuFeedbackEmail": " dev@example.com ", "TessuFeedbackIssuesURL": "https://github.com/me/tessu/issues/new"])
        XCTAssertEqual(c.email, "dev@example.com")
        XCTAssertEqual(c.issuesURL?.host, "github.com")
        XCTAssertTrue(c.destination.contains("dev@example.com")); XCTAssertTrue(c.destination.contains("github.com"))
    }

    func testBadValuesAreIgnored() {
        for bad in ["not-an-email", "a@b", "a b@c.com", "x@y.com, evil@z.com", "x@y.com?cc=evil@z.com", "<x@y.com>"] {
            XCTAssertNil(FeedbackConfig(info: ["TessuFeedbackEmail": bad]).email, bad)
        }
        for bad in ["http://github.com/x", "ftp://x.com", "javascript:alert(1)", "https://", "github.com/x"] {
            XCTAssertNil(FeedbackConfig(info: ["TessuFeedbackIssuesURL": bad]).issuesURL, bad)
        }
    }

    func testMailtoEncodesAndShortensLongText() throws {
        let c = FeedbackConfig(email: "dev@example.com")
        let m = try XCTUnwrap(c.mailto(subject: "Tessu feedback: Idea", body: "Hello & goodbye?\nLine two #1 =x"))
        XCTAssertTrue(m.url.absoluteString.hasPrefix("mailto:dev@example.com?subject="))
        XCTAssertFalse(m.truncated)
        let body = URLComponents(url: m.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value
        XCTAssertEqual(body, "Hello & goodbye?\nLine two #1 =x", "round-trips through encoding exactly")
        let long = try XCTUnwrap(c.mailto(subject: "s", body: String(repeating: "ä ", count: 2000)))
        XCTAssertTrue(long.truncated)
        XCTAssertLessThanOrEqual(long.url.absoluteString.count, 2000, "stays inside what mail clients accept")
    }

    func testIssueUrlKeepsExistingQueryAndCapsBody() throws {
        let c = FeedbackConfig(issuesURL: URL(string: "https://gitlab.example.com/me/app/-/issues/new?issue[confidential]=false"))
        let i = try XCTUnwrap(c.issue(title: "Bug: ", body: String(repeating: "x", count: 9000)))
        XCTAssertTrue(i.truncated)
        XCTAssertTrue(i.url.absoluteString.contains("issue[confidential]=false") || i.url.absoluteString.contains("issue%5Bconfidential%5D=false"))
        XCTAssertTrue(i.url.absoluteString.contains("title=Bug%3A%20"))
    }
}
