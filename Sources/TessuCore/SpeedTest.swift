import Foundation

/// Internet speed test against Cloudflare's public speed endpoints (speed.cloudflare.com).
///  - Ping / jitter: sequential empty requests over a warm connection, minus the server's own processing time.
///  - Download: escalating sizes on parallel streams, bytes counted as they arrive and sampled in short
///    windows; the result is the 90th percentile of those samples (warm-up excluded).
///  - Upload: parallel POSTs. Bytes handed to the socket are not proof of delivery, so each request is
///    timed until Cloudflare answers and its bytes are spread over its own duration.
/// Never throws: problems go in `errors`.
public enum SpeedTest {
    static let base = "https://speed.cloudflare.com"
    static let pingCount = 12
    static let pingTimeout: TimeInterval = 5
    static let downSizes: [Double] = [2e6, 25e6, 50e6] // few, large requests: Cloudflare rate-limits many small ones
    static let downStreams = 3
    static let downByteCap = 100e6
    static let downWarmSize = 10e6
    static let upSizes: [Int] = [100_000, 1_000_000, 5_000_000, 10_000_000]
    static let upWarmStep = 2
    static let upStreams = 3
    static let upByteCap = 50e6
    static let phaseSeconds = 8.0
    static let tickSeconds = 0.1
    static let windowSeconds = 0.5
    static let warmupSeconds = 1.0
    /// Where each phase sits in the overall 0...1 progress.
    static let ranges: [SpeedPhase: (Double, Double)] = [.ping: (0, 0.1), .download: (0.1, 0.55), .upload: (0.55, 1)]

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let idx = min(s.count - 1, max(0, Int((p / 100 * Double(s.count)).rounded(.up)) - 1))
        return s[idx]
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }

    static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
    static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
    static func measId() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased() }
    static func now() -> Double { ProcessInfo.processInfo.systemUptime }

    /// Sum of every "dur=" in the server-timing header, ignoring the cfL4 transport report.
    static func serverDuration(_ header: String?) -> Double {
        var total = 0.0
        for entry in (header ?? "").split(separator: ",") {
            if Rx.test("^\\s*cfL4\\b", String(entry), options: .caseInsensitive) { continue }
            if let m = Rx.first("(?:^|;)\\s*dur=([\\d.]+)", in: String(entry)), let d = Double(m[1]) { total += d }
        }
        return total
    }

    /// The Cloudflare data centre that answered, for the "Server" line.
    static func serverLabel(_ res: HTTPURLResponse) -> String? {
        let ray = Rx.first("-([A-Z]{3})$", in: res.value(forHTTPHeaderField: "cf-ray") ?? "")?[1]
        guard let colo = res.value(forHTTPHeaderField: "cf-meta-colo") ?? ray else { return nil }
        if let city = res.value(forHTTPHeaderField: "cf-meta-city") { return "Cloudflare \(colo) (\(city))" }
        return "Cloudflare \(colo)"
    }

    /// Shared across the phases of one run.
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var _server: String?
        private var _rateLimited = false
        private var _firstError: String?
        var server: String? { lock.lock(); defer { lock.unlock() }; return _server }
        var rateLimited: Bool { lock.lock(); defer { lock.unlock() }; return _rateLimited }
        var firstError: String? { lock.lock(); defer { lock.unlock() }; return _firstError }
        func note(_ res: HTTPURLResponse) {
            lock.lock(); defer { lock.unlock() }
            if _server == nil { _server = serverLabel(res) }
            if res.statusCode == 429 { _rateLimited = true }
        }
        func noteError(_ e: String) { lock.lock(); if _firstError == nil { _firstError = e }; lock.unlock() }
    }

    static func describe(_ error: Error) -> String { errMsg(error) }
    static func isCancel(_ error: Error) -> Bool { (error as? URLError)?.code == .cancelled || error is CancellationError }
}
