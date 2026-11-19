import Foundation

/// Runs the subscription CLIs: status checks and questions. Every function resolves with data and never
/// throws. Processes run in their own process group inside a fresh empty directory, with a 120 s timeout;
/// cancel kills the whole tree.
public final class CLIRunner: @unchecked Sendable {
    public static let shared = CLIRunner()

    static let askTimeout: TimeInterval = 120
    static let probeTimeout: TimeInterval = 10
    static let statusTTL: TimeInterval = 60

    private let lock = NSLock()
    private var statusCache: [ProviderID: (at: Date, value: CLIStatus)] = [:]
    private var inFlight: [ProviderID: Task<CLIStatus, Never>] = [:]
    private var verified = Set<ProviderID>()
    private var lockdownChecked: [String: String?] = [:]
    private var live: [CancelToken] = []
    private var baseDir: URL

    public init(baseDir: URL? = nil) {
        self.baseDir = baseDir ?? FileManager.default.temporaryDirectory.appendingPathComponent("tessu-cli", isDirectory: true)
        // Leftovers from a crash.
        try? FileManager.default.removeItem(at: self.baseDir.appendingPathComponent("runs"))
    }

    // MARK: run directories

    /// A fresh, private directory per CLI run: `cwd` is the empty directory the CLI runs in (nothing for a
    /// model to read), `dir` holds Tessu's own files for that run. cleanup() removes both.
    struct RunDir {
        var dir: URL
        var cwd: URL
        func cleanup() { try? FileManager.default.removeItem(at: dir) }
    }

    func makeRunDir() throws -> RunDir {
        let runs = baseDir.appendingPathComponent("runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let dir = runs.appendingPathComponent("r-" + UUID().uuidString, isDirectory: true)
        let cwd = dir.appendingPathComponent("cwd", isDirectory: true)
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return RunDir(dir: dir, cwd: cwd)
    }

    // MARK: process helper

    func run(_ id: ProviderID, _ exe: String, _ args: [String], input: String? = nil, timeout: TimeInterval,
             cwd: String, cancel: CancelToken? = nil) async -> ExecResult {
        let token = cancel ?? CancelToken()
        lock.lock(); live.append(token); lock.unlock()
        defer { lock.lock(); live.removeAll { $0 === token }; lock.unlock() }
        return await Exec.run(exe, args, timeout: timeout, input: input, env: CLILocator.environment(for: id),
                              cwd: cwd, maxOutput: 4 << 20, killGrace: 5, cancel: token)
    }

    /// App quit: no CLI keeps running (and using the subscription) after Tessu.
    public func killAll() {
        lock.lock(); let tokens = live; live = []; lock.unlock()
        tokens.forEach { $0.cancel() }
    }

    // MARK: state shared with the ask path

    func markVerified(_ id: ProviderID) {
        lock.lock()
        verified.insert(id)
        if var cached = statusCache[id], cached.value.loggedIn != true {
            cached.value.loggedIn = true; cached.value.error = nil
            statusCache[id] = cached
        }
        lock.unlock()
    }

    func isVerified(_ id: ProviderID) -> Bool { lock.lock(); defer { lock.unlock() }; return verified.contains(id) }
    func forget(_ id: ProviderID) { lock.lock(); statusCache[id] = nil; lock.unlock() }
    func cachedLockdown(_ key: String) -> String?? { lock.lock(); defer { lock.unlock() }; return lockdownChecked[key] }
    func storeLockdown(_ key: String, _ problem: String?) { lock.lock(); lockdownChecked[key] = .some(problem); lock.unlock() }
    func cached(_ id: ProviderID) -> (at: Date, value: CLIStatus)? { lock.lock(); defer { lock.unlock() }; return statusCache[id] }
    func store(_ id: ProviderID, _ value: CLIStatus) { lock.lock(); statusCache[id] = (Date(), value); lock.unlock() }

    func joinOrStart(_ id: ProviderID, _ make: @escaping @Sendable () async -> CLIStatus) -> Task<CLIStatus, Never> {
        lock.lock(); defer { lock.unlock() }
        if let t = inFlight[id] { return t }
        let t = Task { await make() }
        inFlight[id] = t
        return t
    }

    func finish(_ id: ProviderID) { lock.lock(); inFlight[id] = nil; lock.unlock() }
}
