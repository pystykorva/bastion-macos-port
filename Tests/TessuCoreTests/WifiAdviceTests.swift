import XCTest
@testable import TessuCore

final class WifiAdviceTests: XCTestCase {
    func testRecommendationMovesToQuietestOf1_6_11() {
        let networks = [wnet(6, .ghz24), wnet(6, .ghz24), wnet(7, .ghz24), wnet(11, .ghz24), wnet(11, .ghz24, pct: 90)]
        let rec = WifiLogic.recommend(networks, band: .ghz24, channel: 6, width: nil)
        XCTAssertEqual(rec?.channel, 1)
        XCTAssertEqual(rec?.neighboursThere, 0)
        XCTAssertEqual(rec?.neighboursNow, 3)
        XCTAssertTrue(rec?.reason.contains("only channels 1, 6 and 11") == true)
        XCTAssertTrue(rec?.reason.contains("assume 20 MHz") == true, "no width reported -> says so")
    }

    func testNoRecommendationWhenAlreadyBest() {
        XCTAssertNil(WifiLogic.recommend([wnet(1, .ghz24)], band: .ghz24, channel: 11, width: 20), "11 is empty and 1 is not better")
        XCTAssertNil(WifiLogic.recommend([], band: .ghz24, channel: 6, width: 20))
        XCTAssertNil(WifiLogic.recommend([wnet(5, .ghz6)], band: .ghz6, channel: 5, width: 20), "6 GHz gets no advice")
        XCTAssertNil(WifiLogic.recommend([], band: nil, channel: nil, width: nil))
    }

    func testDfsOnlyWhenClearlyBetter() {
        // Every non-DFS 5 GHz channel has 2 neighbours, DFS channels have none: at least 2 fewer, so DFS wins.
        var crowded: [WifiNetwork] = []
        for ch in [36, 40, 44, 48, 149, 153, 157, 161, 165] { crowded += [wnet(ch, .ghz5), wnet(ch, .ghz5)] }
        let rec = WifiLogic.recommend(crowded, band: .ghz5, channel: 36, width: 20)
        XCTAssertTrue(WifiLogic.dfs5.contains(rec?.channel ?? 0))
        XCTAssertTrue(rec?.reason.contains("DFS") == true)
        // Only one fewer neighbour somewhere non-DFS: DFS is not worth the radar wait.
        var mild: [WifiNetwork] = []
        for ch in [36, 40, 44, 48, 149, 153, 157, 161, 165] { mild.append(wnet(ch, .ghz5)) }
        mild.append(wnet(36, .ghz5))
        let rec2 = WifiLogic.recommend(mild, band: .ghz5, channel: 36, width: 20)
        XCTAssertFalse(WifiLogic.dfs5.contains(rec2?.channel ?? 0))
    }

    func testMovesInsideTheSameWideBlockAreSkipped() {
        let rec = WifiLogic.recommend([wnet(36, .ghz5), wnet(36, .ghz5)], band: .ghz5, channel: 44, width: 80)
        XCTAssertNotEqual(rec?.channel, 36, "36 and 44 share one 80 MHz block: moving changes nothing")
    }

    func testScoreWeights() {
        func c(_ status: CheckStatus, _ sev: Severity) -> CheckResult {
            CheckResult(id: "x", title: "x", status: status, severity: sev, evidence: "", fix: nil)
        }
        XCTAssertEqual(Scan.score([]), 100)
        XCTAssertEqual(Scan.score([c(.risk, .critical)]), 70)
        XCTAssertEqual(Scan.score([c(.warn, .critical)]), 85, "a warning costs half")
        XCTAssertEqual(Scan.score([c(.risk, .high), c(.risk, .medium), c(.warn, .low)]), 100 - 15 - 8 - 2 + 0, accuracy: 1)
        XCTAssertEqual(Scan.score([c(.ok, .critical), c(.unknown, .critical)]), 100, "ok and unknown never cost points")
        XCTAssertEqual(Scan.score(Array(repeating: c(.risk, .critical), count: 5)), 0, "never below zero")
    }
}

private func XCTAssertEqual(_ a: Int, _ b: Int, accuracy: Int, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(abs(a - b), accuracy, "\(a) vs \(b)", file: file, line: line)
}
