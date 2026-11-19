import Foundation

extension SpeedTest {
    /// Runs ping, download and upload one after the other. `onProgress` gets overall 0...1 progress and the
    /// live value of the running phase. Cancel through `token`; unfinished values stay nil.
    public static func run(token: CancelToken = CancelToken(), onProgress: @escaping @Sendable (SpeedProgress) -> Void = { _ in }) async -> SpeedResult {
        let state = State()
        var result = await execute(token: token, state: state, onProgress: onProgress)
        if state.rateLimited && !result.errors.contains(where: { $0.contains("HTTP 429") }) {
            result.errors.append("Cloudflare rate-limited part of the test (HTTP 429), so this result may read low. Wait a few minutes and run it again.")
        }
        result.server = state.server ?? "Cloudflare"
        // Always the last event, also after a failure or cancel.
        onProgress(SpeedProgress(phase: .done, mbps: nil, pingMs: result.pingMs, progress: 1))
        return result
    }

    private static func execute(token: CancelToken, state: State, onProgress: @escaping @Sendable (SpeedProgress) -> Void) async -> SpeedResult {
        var result = SpeedResult()

        // Maps phase-local progress (0...1) to overall progress.
        @Sendable func overall(_ p: SpeedProgress) -> SpeedProgress {
            let (a, b) = ranges[p.phase] ?? (0, 1)
            var q = p
            q.progress = round2(a + (b - a) * min(1, max(0, p.progress)))
            return q
        }
        let emit: @Sendable (SpeedProgress) -> Void = { onProgress(overall($0)) }

        emit(SpeedProgress(phase: .ping, mbps: nil, pingMs: nil, progress: 0))
        guard let ping = await runPing(token: token, state: state, emit: emit) else {
            if token.isCancelled { result.errors.append("Speed test cancelled. Values that were not finished are left empty."); return result }
            result.errors.append(state.rateLimited
                ? "speed.cloudflare.com is rate-limiting this connection (HTTP 429), so no test was run. Wait a few minutes and try again."
                : "Could not reach speed.cloudflare.com" + (state.firstError.map { ": \($0)" } ?? "") +
                  ". Check that this computer is online and that a firewall or VPN is not blocking it.")
            return result
        }
        result.pingMs = ping.pingMs
        result.jitterMs = ping.jitterMs
        if token.isCancelled { result.errors.append("Speed test cancelled. Values that were not finished are left empty."); return result }

        let down = await runDownload(token: token, state: state, emit: emit)
        if token.isCancelled { result.errors.append("Speed test cancelled. Values that were not finished are left empty."); return result }
        if let e = down.error { result.errors.append("Download was not measured: \(e)") }
        else {
            result.downMbps = down.mbps
            if let w = down.warning { result.errors.append("Download: \(w)") }
        }

        let up = await runUpload(token: token, state: state, emit: emit)
        if token.isCancelled { result.errors.append("Speed test cancelled. Values that were not finished are left empty."); return result }
        if let e = up.error { result.errors.append("Upload was not measured: \(e)") }
        else {
            result.upMbps = up.mbps
            if let w = up.warning { result.errors.append("Upload: \(w)") }
        }
        return result
    }
}
