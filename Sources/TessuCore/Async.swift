import Foundation

/// Runs `transform` over `items` with at most `limit` in flight; results keep input order.
func mapLimit<T: Sendable, R: Sendable>(_ items: [T], limit: Int, _ transform: @escaping @Sendable (T) async -> R) async -> [R] {
    var results = [R?](repeating: nil, count: items.count)
    await withTaskGroup(of: (Int, R).self) { group in
        var next = 0
        func addNext() {
            guard next < items.count else { return }
            let i = next
            next += 1
            group.addTask { (i, await transform(items[i])) }
        }
        for _ in 0..<min(limit, items.count) { addNext() }
        while let (i, r) = await group.next() {
            results[i] = r
            addNext()
        }
    }
    return results.map { $0! }
}

/// Resolves with the operation's value, or `fallback` after `seconds`.
func withTimeout<T: Sendable>(_ seconds: TimeInterval, fallback: T, _ op: @escaping @Sendable () async -> T) async -> T {
    await withTaskGroup(of: T.self) { group in
        group.addTask { await op() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return fallback
        }
        let first = await group.next() ?? fallback
        group.cancelAll()
        return first
    }
}

func errMsg(_ error: Error) -> String { (error as NSError).localizedDescription }

/// Runs blocking work on a global queue so the cooperative thread pool is never stalled.
func blocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: work()) }
    }
}

func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
