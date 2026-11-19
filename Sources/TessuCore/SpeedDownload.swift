import Foundation

extension SpeedTest {
    struct PhaseResult {
        var mbps: Double
        var error: String?
        var warning: String?
    }

    /// Three parallel streams per size. The result is the 90th percentile of windowed rates after warm-up,
    /// so a gigabit link that hits the byte cap in under a second is not measured during TCP slow start.
    static func runDownload(token: CancelToken, state: State, emit: @escaping @Sendable (SpeedProgress) -> Void) async -> PhaseResult {
        let phase = CancelToken()
        token.onCancel { phase.cancel() }
        let counter = ByteCounter()
        let start = now()
        let sampler = ThroughputSampler(start: start, window: windowSeconds)

        let ticker = Task.detached {
            while !Task.isCancelled && !phase.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(tickSeconds * 1e9))
                let t = now()
                let bytes = counter.bytes
                if t - start >= warmupSeconds { sampler.endWarmup(at: t, bytes: bytes) }
                let live = sampler.tick(at: t, bytes: bytes)
                if bytes >= downByteCap { phase.cancel() }
                let progress = min(1, max((t - start) / phaseSeconds, bytes / downByteCap))
                emit(SpeedProgress(phase: .download, mbps: round2(live), pingMs: nil, progress: progress))
            }
        }
        let stopper = Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(phaseSeconds * 1e9))
            phase.cancel()
        }
        var firstError: String?
        sizes: for size in downSizes {
            if phase.isCancelled { break }
            if size >= downWarmSize { sampler.endWarmup(at: now(), bytes: counter.bytes) }
            let errors = await withTaskGroup(of: String?.self) { group -> [String] in
                for _ in 0..<downStreams {
                    group.addTask {
                        guard let url = URL(string: "\(base)/__down?bytes=\(Int(size))&measId=\(measId())") else { return "bad URL" }
                        do { try await StreamDownload(counter: counter, state: state).run(url: url, token: phase); return nil }
                        catch { return (isCancel(error) || phase.isCancelled) ? nil : describe(error) }
                    }
                }
                var out: [String] = []
                for await e in group { if let e = e { out.append(e) } }
                return out
            }
            if firstError == nil { firstError = errors.first }
            if counter.bytes == 0, firstError != nil { break sizes } // nothing works; do not keep hammering
        }

        // No event may leave after this point: the next phase and the final "done" must stay in order.
        ticker.cancel(); stopper.cancel()
        await ticker.value

        let bytes = counter.bytes
        if bytes == 0 { return PhaseResult(mbps: 0, error: firstError ?? "no data received", warning: nil) }
        let (samples, warm) = sampler.snapshot()
        let lastAt = counter.lastAt
        let mbps: Double
        if samples.count >= 3 {
            mbps = percentile(samples, 90)
        } else if let w = warm, lastAt - w.t >= 0.2, bytes > w.bytes {
            // Too few windows (fast link hitting the byte cap early): average after warm-up only, so TLS
            // setup, slow start and the small first rounds do not drag the figure down.
            mbps = (bytes - w.bytes) * 8 / (lastAt - w.t) / 1e6
        } else {
            // Very little data overall: average over the whole phase, which is conservative.
            mbps = bytes * 8 / max(0.001, lastAt - start) / 1e6
        }
        let warning = firstError.map { "some download streams failed (\($0)), so the result may read low." }
        return PhaseResult(mbps: round2(mbps), error: nil, warning: warning)
    }
}
