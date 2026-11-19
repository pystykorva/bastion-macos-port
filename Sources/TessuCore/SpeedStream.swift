import Foundation

/// Thread-safe byte counter fed by URLSession delegate callbacks.
final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _bytes = 0.0
    private var _lastAt = 0.0

    var bytes: Double { lock.lock(); defer { lock.unlock() }; return _bytes }
    var lastAt: Double { lock.lock(); defer { lock.unlock() }; return _lastAt }

    func add(_ n: Int) {
        lock.lock(); _bytes += Double(n); _lastAt = SpeedTest.now(); lock.unlock()
    }
}

/// One streaming download. Bytes are counted as they arrive (not when the body is complete), which is
/// what makes a windowed throughput measurement possible.
final class StreamDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let counter: ByteCounter
    private let state: SpeedTest.State
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()
    private var done = false

    init(counter: ByteCounter, state: SpeedTest.State) {
        self.counter = counter
        self.state = state
    }

    /// Resolves when the body ended; throws on failure or cancel.
    func run(url: URL, token: CancelToken) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.dataTask(with: req)
        self.task = task
        token.onCancel { task.cancel() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.lock(); continuation = cont; lock.unlock()
            task.resume()
        }
    }

    private func finish(_ error: Error?) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        let c = continuation
        continuation = nil
        lock.unlock()
        session?.invalidateAndCancel()
        if let e = error { c?.resume(throwing: e) } else { c?.resume() }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            state.note(http)
            if !(200..<300).contains(http.statusCode) {
                finish(NSError(domain: "SpeedTest", code: http.statusCode,
                               userInfo: [NSLocalizedDescriptionKey: "download HTTP \(http.statusCode)"]))
                completionHandler(.cancel)
                return
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        counter.add(data.count)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error)
    }
}
