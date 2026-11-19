import Foundation
import Darwin

// Process supervision for Exec: output collection, stdin feeding, timeout, cancel, tree kill.

extension Exec {
    static func start(path: String, args: [String], options: Options, token: CancelToken,
                      completion: @escaping (ExecResult) -> Void) {
        guard let spawned = spawn(path: path, args: args, env: options.env, cwd: options.cwd) else {
            var r = ExecResult()
            r.error = "\(URL(fileURLWithPath: path).lastPathComponent) could not start (errno \(errno))"
            completion(r)
            return
        }
        let job = Job()
        job.pid = spawned.pid
        let group = DispatchGroup()

        @Sendable func finish() {
            job.lock.lock()
            if job.finished { job.lock.unlock(); return }
            job.finished = true
            var r = ExecResult()
            r.stdout = String(decoding: job.stdout, as: UTF8.self)
            r.stderr = String(decoding: job.stderr, as: UTF8.self)
            r.code = job.code
            r.timedOut = job.timedOut
            r.aborted = job.aborted
            job.lock.unlock()
            completion(r)
        }

        @Sendable func killTree(_ signal: Int32) {
            if kill(-job.pid, signal) != 0 { _ = kill(job.pid, signal) }
        }

        @Sendable func stop() {
            killTree(SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { killTree(SIGKILL) }
            // A grandchild may keep the pipes open; resolve anyway.
            DispatchQueue.global().asyncAfter(deadline: .now() + options.killGrace) { finish() }
        }

        collect(fd: spawned.stdout, isOut: true, job: job, group: group, limit: options.maxOutput)
        collect(fd: spawned.stderr, isOut: false, job: job, group: group, limit: options.maxOutput)
        feed(fd: spawned.stdin, input: options.input)

        group.enter()
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(job.pid, &status, 0) < 0 && errno == EINTR {}
            job.lock.lock()
            // WIFEXITED: the low 7 bits are zero. A signalled child has no exit code.
            if status & 0x7f == 0 { job.code = (status >> 8) & 0xff }
            job.lock.unlock()
            group.leave()
        }
        group.notify(queue: .global()) { finish() }

        DispatchQueue.global().asyncAfter(deadline: .now() + options.timeout) {
            job.lock.lock()
            let done = job.finished
            if !done { job.timedOut = true }
            job.lock.unlock()
            if !done { stop() }
        }
        token.onCancel {
            job.lock.lock()
            let done = job.finished
            if !done { job.aborted = true }
            job.lock.unlock()
            if !done { stop() }
        }
    }

    private static func collect(fd: Int32, isOut: Bool, job: Job, group: DispatchGroup, limit: Int) {
        group.enter()
        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let n = read(fd, &buffer, buffer.count)
                if n > 0 {
                    job.lock.lock()
                    if isOut {
                        if job.stdout.count < limit { job.stdout.append(contentsOf: buffer[0..<n]) }
                    } else if job.stderr.count < limit {
                        job.stderr.append(contentsOf: buffer[0..<n])
                    }
                    job.lock.unlock()
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
            close(fd)
            group.leave()
        }
    }

    /// Writes the prompt to the child's stdin, then closes it so the child sees EOF.
    private static func feed(fd: Int32, input: String?) {
        guard let input = input, !input.isEmpty else { close(fd); return }
        Thread.detachNewThread {
            let bytes = Array(input.utf8)
            var offset = 0
            while offset < bytes.count {
                let n = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
                if n > 0 { offset += n } else if n < 0 && errno == EINTR { continue } else { break }
            }
            close(fd)
        }
    }
}
