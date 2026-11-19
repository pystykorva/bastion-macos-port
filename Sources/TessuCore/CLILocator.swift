import Foundation

/// Finds the subscription CLIs. Apps started from the Dock get a minimal PATH, so the usual install
/// locations are searched explicitly as well.
public enum CLILocator {
    public struct Spec: Sendable {
        public var bin: String
        public var product: String
        public var vendor: String
        public var plan: String
        public var install: String
        public var login: String
    }

    public static func spec(_ id: ProviderID) -> Spec? {
        switch id {
        case .claudeCli:
            return Spec(bin: "claude", product: "Claude Code", vendor: "Anthropic", plan: "Claude",
                        install: "npm install -g @anthropic-ai/claude-code", login: "claude auth login")
        case .codexCli:
            return Spec(bin: "codex", product: "Codex", vendor: "OpenAI", plan: "ChatGPT",
                        install: "npm install -g @openai/codex", login: "codex login")
        default: return nil
        }
    }

    /// Valid model ids only: they end up in argv.
    public static let modelPattern = "^[A-Za-z0-9][A-Za-z0-9._:/\\[\\]-]{0,99}$"
    public static func isValidModel(_ m: String) -> Bool { Rx.test(modelPattern, m) }

    static func searchDirs(home: String = NSHomeDirectory(), path: String = ProcessInfo.processInfo.environment["PATH"] ?? "") -> [String] {
        var dirs: [String] = []
        func add(_ d: String) { if !d.isEmpty, d.hasPrefix("/"), !dirs.contains(d) { dirs.append(d) } }
        path.split(separator: ":").forEach { add(String($0).trimmingCharacters(in: .whitespaces)) }
        add("/opt/homebrew/bin")
        add("/usr/local/bin")
        add("\(home)/.local/bin")
        add("\(home)/.npm-global/bin")
        add("\(home)/.claude/local")
        add("\(home)/.volta/bin")
        add("\(home)/Library/pnpm")
        add("\(home)/.bun/bin")
        // nvm: every installed Node version's bin directory.
        let nvm = "\(home)/.nvm/versions/node"
        for v in (try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? [] { add("\(nvm)/\(v)/bin") }
        add("/usr/bin")
        add("/bin")
        return dirs
    }

    public static func find(_ bin: String, in dirs: [String]? = nil) -> String? {
        let fm = FileManager.default
        for dir in dirs ?? searchDirs() {
            let p = (dir as NSString).appendingPathComponent(bin)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue, fm.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Environment for a CLI run: the usual PATH plus install locations (so `#!/usr/bin/env node` shims work),
    /// no colour, and for Claude no API key from the environment, so the subscription login is what gets used
    /// (Claude Code prefers ANTHROPIC_API_KEY when it is set).
    static func environment(for id: ProviderID, base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        env["PATH"] = searchDirs(path: base["PATH"] ?? "").joined(separator: ":")
        env["NO_COLOR"] = "1"
        if id == .claudeCli {
            env["ANTHROPIC_API_KEY"] = nil
            env["ANTHROPIC_AUTH_TOKEN"] = nil
        }
        return env
    }
}
