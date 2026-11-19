import Foundation

/// Completed upload requests, kept to compute delivered rate per time window.
final class UploadLedger: @unchecked Sendable {
    struct Done { var t0: Double; var t1: Double; var bytes: Double }
    private let lock = NSLock()
    private var done: [Done] = []
    private var issued = 0.0
    private var completed = 0.0
    private var warmAt: Double
    private var latest: [Double?]

    init(start: Double, streams: Int, warmup: Double) {
        warmAt = start + warmup
        latest = Array(repeating: nil, count: streams)
    }

    var issuedBytes: Double { lock.lock(); defer { lock.unlock() }; return issued }
    var completedBytes: Double { lock.lock(); defer { lock.unlock() }; return completed }
    var doneCount: Int { lock.lock(); defer { lock.unlock() }; return done.count }
    var warmStart: Double { lock.lock(); defer { lock.unlock() }; return warmAt }
    func latestRate(_ i: Int) -> Double? { lock.lock(); defer { lock.unlock() }; return latest[i] }

    func issue(_ size: Int, at t0: Double, step: Int, warmStep: Int) {
        lock.lock(); defer { lock.unlock() }
        issued += Double(size)
        if step >= warmStep && t0 < warmAt { warmAt = t0 }
    }

    func complete(stream: Int, size: Int, t0: Double, t1: Double) {
        lock.lock(); defer { lock.unlock() }
        done.append(Done(t0: t0, t1: t1, bytes: Double(size)))
        completed += Double(size)
        latest[stream] = Double(size) * 8 / max(0.001, t1 - t0) / 1e6
    }

    /// Mbps delivered in [a, b], crediting each finished request's bytes evenly across its duration.
    func rate(_ a: Double, _ b: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        var bytes = 0.0
        for r in done {
            let overlap = min(b, r.t1) - max(a, r.t0)
            if overlap > 0 { bytes += r.bytes * overlap / (r.t1 - r.t0) }
        }
        return bytes * 8 / (b - a) / 1e6
    }

    var span: (first: Double, last: Double)? {
        lock.lock(); defer { lock.unlock() }
        guard let f = done.map(\.t0).min(), let l = done.map(\.t1).max() else { return nil }
        return (f, l)
    }
}

/// One upload POST, timed until the server has answered.
enum UploadRequest {
    static func send(size: Int, body: Data, state: SpeedTest.State, token: CancelToken) async throws -> (status: Int, finishedAt: Double) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let url = URL(string: "\(SpeedTest.base)/__up?measId=\(SpeedTest.measId())") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let box = TaskBox()
        token.onCancel { box.cancel() }
        return try await withCheckedThrowingContinuation { cont in
            let task = session.uploadTask(with: req, from: body) { _, response, error in
                let t1 = SpeedTest.now()
                if let error = error { cont.resume(throwing: error); return }
                guard let http = response as? HTTPURLResponse else { cont.resume(throwing: URLError(.badServerResponse)); return }
                state.note(http)
                cont.resume(returning: (http.statusCode, t1))
            }
            box.set(task)
            task.resume()
        }
    }
}

final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false
    func set(_ t: URLSessionTask) {
        lock.lock(); task = t; let c = cancelled; lock.unlock()
        if c { t.cancel() }
    }
    func cancel() {
        lock.lock(); cancelled = true; let t = task; lock.unlock()
        t?.cancel()
    }
}
