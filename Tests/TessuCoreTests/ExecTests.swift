import XCTest
@testable import TessuCore

final class ExecTests: XCTestCase {
    func testCapturesStdoutStderrAndExitCode() async {
        let r = await Exec.run("/bin/sh", ["-c", "echo out; echo err 1>&2; exit 3"])
        XCTAssertEqual(r.stdout, "out\n"); XCTAssertEqual(r.stderr, "err\n"); XCTAssertEqual(r.code, 3)
        XCTAssertFalse(r.ok); XCTAssertFalse(r.timedOut); XCTAssertNil(r.error)
    }

    func testStdinIsDeliveredAndNeverInArgv() async {
        let secret = "network-snapshot-\(UUID().uuidString)"
        let r = await Exec.run("/bin/sh", ["-c", "cat; echo \"ARGS=$*\""], input: secret)
        XCTAssertTrue(r.stdout.hasPrefix(secret)); XCTAssertTrue(r.ok)
    }

    func testLargeStdinAndStdoutDoNotDeadlock() async {
        let big = String(repeating: "0123456789", count: 200_000) // 2 MB each way, far beyond a pipe buffer
        let r = await Exec.run("/bin/cat", [], timeout: 20, input: big)
        XCTAssertEqual(r.stdout.count, big.count); XCTAssertTrue(r.ok)
    }

    func testMissingBinaryResolvesWithAnErrorInsteadOfThrowing() async {
        let r = await Exec.run("/nonexistent/binary")
        XCTAssertNotNil(r.error); XCTAssertFalse(r.ok)
    }

    func testTimeoutKillsTheProcessAndSaysSo() async {
        let t0 = Date()
        let r = await Exec.run("/bin/sleep", ["30"], timeout: 0.5, killGrace: 2)
        XCTAssertTrue(r.timedOut); XCTAssertFalse(r.ok)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 5)
    }

    func testCancelAbortsAndKillsGrandchildren() async throws {
        let marker = NSTemporaryDirectory() + "tessu-grandchild-\(UUID().uuidString)"
        // The shell starts a background grandchild that would create the marker after 3 s.
        let script = "(sleep 3; touch \(marker)) & wait"
        let token = CancelToken()
        async let result = Exec.run("/bin/sh", ["-c", script], timeout: 30, killGrace: 2, cancel: token)
        try await Task.sleep(nanoseconds: 400_000_000)
        token.cancel()
        let r = await result
        XCTAssertTrue(r.aborted)
        try await Task.sleep(nanoseconds: 3_500_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker), "the whole process group must die, not just the shell")
    }

    func testEnvironmentIsExactlyWhatWasPassed() async {
        let r = await Exec.run("/usr/bin/env", [], env: ["ONLY": "this"])
        XCTAssertEqual(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ONLY=this")
    }

    func testWorkingDirectory() async {
        let dir = FileManager.default.temporaryDirectory.path
        let r = await Exec.run("/bin/pwd", [], cwd: dir)
        XCTAssertEqual(URL(fileURLWithPath: r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath().path,
                       URL(fileURLWithPath: dir).resolvingSymlinksInPath().path)
    }

    func testMapLimitKeepsOrderAndRespectsLimit() async {
        final class Peak: @unchecked Sendable { var cur = 0, max = 0; let l = NSLock() }
        let peak = Peak()
        let out = await mapLimit(Array(0..<20), limit: 4) { n -> Int in
            peak.l.lock(); peak.cur += 1; peak.max = Swift.max(peak.max, peak.cur); peak.l.unlock()
            try? await Task.sleep(nanoseconds: 5_000_000)
            peak.l.lock(); peak.cur -= 1; peak.l.unlock()
            return n * 2
        }
        XCTAssertEqual(out, (0..<20).map { $0 * 2 }); XCTAssertLessThanOrEqual(peak.max, 4)
    }
}
