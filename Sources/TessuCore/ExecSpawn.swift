import Foundation
import Darwin

// posix_spawn plumbing for Exec. Kept apart from the public API in Exec.swift.

struct SpawnedProcess {
    let pid: pid_t
    let stdin: Int32
    let stdout: Int32
    let stderr: Int32
}

extension Exec {
    static func spawn(path: String, args: [String], env: [String: String]?, cwd: String?) -> SpawnedProcess? {
        var inP: [Int32] = [0, 0], outP: [Int32] = [0, 0], errP: [Int32] = [0, 0]
        guard pipe(&inP) == 0 else { return nil }
        guard pipe(&outP) == 0 else { close(inP[0]); close(inP[1]); return nil }
        guard pipe(&errP) == 0 else {
            close(inP[0]); close(inP[1]); close(outP[0]); close(outP[1]); return nil
        }
        // Only the dup2'd descriptors may reach the child; our own ends close on exec.
        for fd in inP + outP + errP { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }

        var fileActions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, inP[0], 0)
        posix_spawn_file_actions_adddup2(&fileActions, outP[1], 1)
        posix_spawn_file_actions_adddup2(&fileActions, errP[1], 2)
        if let cwd = cwd { posix_spawn_file_actions_addchdir_np(&fileActions, cwd) }

        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Own process group (so the tree can be killed). Ignored signals and a blocked signal mask are
        // inherited across exec, so the child starts with every disposition at its default and an empty
        // mask: otherwise a parent that ignores SIGTERM/SIGPIPE would make cancel and timeout unreliable.
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attr, &allSignals)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attr, &noSignals)
        let flags = Int32(POSIX_SPAWN_SETPGROUP) | Int32(POSIX_SPAWN_SETSIGDEF) | Int32(POSIX_SPAWN_SETSIGMASK)
        posix_spawnattr_setflags(&attr, Int16(truncatingIfNeeded: flags))
        posix_spawnattr_setpgroup(&attr, 0)

        let argv: [UnsafeMutablePointer<CChar>?] = ([path] + args).map { strdup($0) } + [nil]
        let environment = env ?? ProcessInfo.processInfo.environment
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, path, &fileActions, &attr, argv, envp)
        // The child's ends are closed in the parent either way.
        close(inP[0]); close(outP[1]); close(errP[1])
        if rc != 0 {
            close(inP[1]); close(outP[0]); close(errP[0])
            errno = rc
            return nil
        }
        return SpawnedProcess(pid: pid, stdin: inP[1], stdout: outP[0], stderr: errP[0])
    }
}
