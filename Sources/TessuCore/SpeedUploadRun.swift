import Foundation

extension SpeedTest {
    /// 1 MiB of incompressible data, sliced to the size of each request.
    private static let randomBlock: Data = {
        var bytes = [UInt8](repeating: 0, count: 1 << 20)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }()

    static func uploadBody(_ size: Int) -> Data {
        if size <= randomBlock.count { return randomBlock.prefix(size) }
        var out = Data(capacity: size)
        var left = size
        while left > 0 { out.append(randomBlock.prefix(min(randomBlock.count, left))); left -= randomBlock.count }
        return out
    }

    /// Three parallel streams of POSTs that start small (so a slow uplink still finishes requests within
    /// the phase) and grow while each one completes in under 1.5 s.
    static func runUpload(token: CancelToken, state: State, emit: @escaping @Sendable (SpeedProgress) -> Void) async -> PhaseResult {
        let phase = CancelToken()
        token.onCancel { phase.cancel() }
        let start = now()
        let ledger = UploadLedger(start: start, streams: upStreams, warmup: warmupSeconds)
        let bodies = upSizes.reduce(into: [Int: Data]()) { $0[$1] = uploadBody($1) }

        let ticker = Task.detached {
            while !Task.isCancelled && !phase.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(tickSeconds * 1e9))
                let t = now()
                var live = 0.0
                if let span = ledger.span {
                    // The live figure trails slightly: it covers the second before the latest confirmed upload.
                    live = ledger.rate(max(start, span.last - 1), span.last)
                }
                let progress = min(1, max((t - start) / phaseSeconds, ledger.issuedBytes / upByteCap))
                emit(SpeedProgress(phase: .upload, mbps: round2(live), pingMs: nil, progress: progress))
            }
        }
        let stopper = Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(phaseSeconds * 1e9))
            phase.cancel()
        }
        let firstError = await withTaskGroup(of: String?.self) { group -> String? in
            for idx in 0..<upStreams {
                group.addTask { await uploadStream(idx, start: start, ledger: ledger, bodies: bodies, state: state, phase: phase) }
            }
            var first: String?
            for await e in group where first == nil { first = e }
            return first
        }

        ticker.cancel(); stopper.cancel()
        await ticker.value

        if ledger.completedBytes == 0 {
            return PhaseResult(
                mbps: 0,
                error: firstError ?? "not even a 100 kB upload finished within 8 seconds, so the uplink is very slow (well under 1 Mbps) or stalled",
                warning: nil)
        }
        guard let span = ledger.span else { return PhaseResult(mbps: 0, error: "no upload finished", warning: nil) }
        let warmAt = ledger.warmStart
        var samples: [Double] = []
        var a = warmAt
        while a + windowSeconds <= span.last { samples.append(ledger.rate(a, a + windowSeconds)); a += tickSeconds }
        let mbps: Double
        if samples.count >= 3 { mbps = percentile(samples, 90) }
        else if span.last - warmAt >= 0.2 { mbps = ledger.rate(warmAt, span.last) } // too few windows: average after warm-up
        else { mbps = ledger.rate(span.first, span.last) } // very little data: overall average, which is conservative
        // Requests cut off at the end of the phase are not counted, so only a few completions means a floor.
        let warning: String? = ledger.doneCount < upStreams * 2
            ? "only a few uploads finished before the time limit, so this is a lower bound."
            : firstError.map { "some upload requests failed (\($0)), so the result may read low." }
        return PhaseResult(mbps: round2(mbps), error: nil, warning: warning)
    }

    private static func uploadStream(_ idx: Int, start: Double, ledger: UploadLedger, bodies: [Int: Data],
                                     state: State, phase: CancelToken) async -> String? {
        var step = 0
        var firstError: String?
        while !phase.isCancelled && ledger.issuedBytes < upByteCap {
            var size = upSizes[step]
            let remaining = phaseSeconds - (now() - start)
            // Do not start a request that cannot finish before the phase ends at the current rate.
            if let rate = ledger.latestRate(idx), step > 0, Double(size) * 8 / (rate * 1e6) > remaining { step -= 1; size = upSizes[step] }
            let t0 = now()
            ledger.issue(size, at: t0, step: step, warmStep: upWarmStep)
            do {
                let r = try await UploadRequest.send(size: size, body: bodies[size] ?? uploadBody(size), state: state, token: phase)
                if !(200..<300).contains(r.status) {
                    return firstError ?? "upload HTTP \(r.status)"
                }
                // No server-timing subtraction here: Cloudflare's worker time includes receiving the body.
                ledger.complete(stream: idx, size: size, t0: t0, t1: r.finishedAt)
                if r.finishedAt - t0 < 1.5 && step < upSizes.count - 1 { step += 1 }
            } catch {
                if isCancel(error) || phase.isCancelled { break }
                if firstError == nil { firstError = describe(error) }
                if ledger.completedBytes == 0 { return firstError }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        return firstError
    }
}
