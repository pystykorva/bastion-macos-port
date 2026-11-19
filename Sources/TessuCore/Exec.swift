import Foundation
import Darwin

/// Cooperative cancellation for a running subprocess or request.
public final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [() -> Void] = []

    public init() {}

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        if cancelled { lock.unlock(); return }
        cancelled = true
        let hs = handlers
        handlers = []
        lock.unlock()
        hs.forEach { $0() }
    }

    /// Runs `handler` once, immediately if the token is already cancelled.
    public func onCancel(_ handler: @escaping () -> Void) {
        lock.lock()
        if cancelled { lock.unlock(); handler(); return }
        handlers.append(handler)
        lock.unlock()
    }
}

public struct ExecResult: Sendable {
    public var stdout = ""
    public var stderr = ""
    /// Exit status, or nil when the process was killed by a signal or never started.
    public var code: Int32?
    public var timedOut = false
    public var aborted = false
    public var error: String?

    public var ok: Bool { error == nil && code == 0 && !timedOut && !aborted }
}

/// Runs subprocesses without a shell (posix_spawn), each in its own process group so a timeout
/// or cancel can kill the whole tree. Every call resolves with data and never throws.
public enum Exec {
    public static let defaultTimeout: TimeInterval = 8

    public static func run(
        _ path: String,
        _ args: [String] = [],
        timeout: TimeInterval = defaultTimeout,
        input: String? = nil,
        env: [String: String]? = nil,
        cwd: String? = nil,
        maxOutput: Int = 32 << 20,
        killGrace: TimeInterval = 5,
        cancel: CancelToken? = nil
    ) async -> ExecResult {
        let token = cancel ?? CancelToken()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<ExecResult, Never>) in
                let opts = Options(timeout: timeout, input: input, env: env, cwd: cwd, maxOutput: maxOutput, killGrace: killGrace)
                start(path: path, args: args, options: opts, token: token) { cont.resume(returning: $0) }
            }
        } onCancel: {
            token.cancel()
        }
    }

    struct Options {
        var timeout: TimeInterval
        var input: String?
        var env: [String: String]?
        var cwd: String?
        var maxOutput: Int
        var killGrace: TimeInterval
    }

    /// Shared mutable state of one running process.
    final class Job: @unchecked Sendable {
        let lock = NSLock()
        var stdout = Data()
        var stderr = Data()
        var finished = false
        var timedOut = false
        var aborted = false
        var code: Int32?
        var pid: pid_t = 0
    }
}
