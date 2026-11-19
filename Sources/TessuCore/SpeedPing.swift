import Foundation

extension SpeedTest {
    /// Round-trip time and jitter. One warm-up request opens the TLS connection, so the samples
    /// measure round trips and not handshakes.
    static func runPing(token: CancelToken, state: State, emit: @Sendable (SpeedProgress) -> Void) async -> (pingMs: Double, jitterMs: Double)? {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = pingTimeout
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var rtts: [Double] = []
        var failures = 0
        for i in 0...pingCount {
            if token.isCancelled { break }
            guard let url = URL(string: "\(base)/__down?bytes=0&measId=\(measId())") else { break }
            let t0 = now()
            do {
                let (_, response) = try await session.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: pingTimeout))
                let t1 = now()
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                state.note(http)
                if !(200..<300).contains(http.statusCode) { throw NSError(domain: "SpeedTest", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]) }
                if i > 0 {
                    let serverMs = serverDuration(http.value(forHTTPHeaderField: "server-timing"))
                    rtts.append(max(0.1, (t1 - t0) * 1000 - serverMs))
                    emit(SpeedProgress(phase: .ping, mbps: nil, pingMs: round1(median(rtts)), progress: Double(i) / Double(pingCount)))
                }
            } catch {
                if token.isCancelled { break }
                failures += 1
                state.noteError(describe(error))
                if failures >= 3 && rtts.isEmpty { break }
            }
        }
        guard !rtts.isEmpty else { return nil }
        var diff = 0.0
        for i in 1..<max(rtts.count, 1) where rtts.count > 1 { diff += abs(rtts[i] - rtts[i - 1]) }
        return (round1(median(rtts)), rtts.count > 1 ? round1(diff / Double(rtts.count - 1)) : 0)
    }
}
