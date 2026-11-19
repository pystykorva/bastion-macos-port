import Foundation

/// Windowed throughput sampler. Synchronous on purpose: its lock is never held across an await.
final class ThroughputSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var marks: [(t: Double, bytes: Double)]
    private var samples: [Double] = []
    private var warm: (t: Double, bytes: Double)?
    private var live = 0.0
    private let window: Double

    init(start: Double, window: Double) {
        marks = [(start, 0)]
        self.window = window
    }

    func endWarmup(at t: Double, bytes: Double) {
        lock.lock(); defer { lock.unlock() }
        if warm == nil { warm = (t, bytes) }
    }

    /// Records a reading and returns the current live rate in Mbps.
    func tick(at t: Double, bytes: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        marks.append((t, bytes))
        while marks.count > 2 && t - marks[1].t >= window { marks.removeFirst() }
        let first = marks[0]
        let dt = t - first.t
        if dt >= window * 0.8 {
            live = (bytes - first.bytes) * 8 / dt / 1e6
            // Only windows that lie entirely after warm-up count toward the result.
            if let w = warm, first.t >= w.t { samples.append(live) }
        }
        return live
    }

    func snapshot() -> (samples: [Double], warm: (t: Double, bytes: Double)?) {
        lock.lock(); defer { lock.unlock() }
        return (samples, warm)
    }
}
