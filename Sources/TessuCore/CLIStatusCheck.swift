import Foundation

extension CLIRunner {
    static func firstVersion(_ text: String) -> String? {
        Rx.first("\\d+\\.\\d+\\.\\d+[0-9A-Za-z.+-]*", in: text)?[0]
    }

    static func stripAnsi(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
    }

    /// Installed? Signed in? Cached for 60 s (5 s while not ready, so installing or signing in shows up
    /// after "Check again" without restarting Tessu).
    public func status(_ id: ProviderID, force: Bool = false) async -> CLIStatus {
        guard CLILocator.spec(id) != nil else {
            var s = CLIStatus(); s.error = "Unknown provider."; return s
        }
        if !force, let c = cached(id) {
            let ttl = c.value.installed && c.value.loggedIn != false ? Self.statusTTL : 5
            if Date().timeIntervalSince(c.at) < ttl { return c.value }
        }
        let task = joinOrStart(id) { [self] in await detect(id) }
        let value = await task.value
        finish(id)
        store(id, value)
        return value
    }

    func detect(_ id: ProviderID) async -> CLIStatus {
        guard let spec = CLILocator.spec(id) else { return CLIStatus() }
        var out = CLIStatus()
        out.product = spec.product; out.installCommand = spec.install; out.loginCommand = spec.login
        guard let exe = CLILocator.find(spec.bin) else {
            out.error = "\(spec.product) isn't installed. Install it with: \(spec.install)"
            return out
        }
        out.path = exe
        guard let rd = try? makeRunDir() else { out.error = "Tessu could not create a work folder for \(spec.product)."; return out }
        defer { rd.cleanup() }
        let cwd = rd.cwd.path

        let v = await run(id, exe, ["--version"], timeout: Self.probeTimeout, cwd: cwd)
        guard v.code == 0 else {
            let why = v.timedOut ? "it did not respond" : (v.error ?? Self.stripAnsi(v.stderr).split(separator: "\n").first.map(String.init) ?? "exit code \(v.code.map(String.init) ?? "?")")
            out.error = "\(spec.product) was found at \(exe) but could not start (\(String(why.prefix(160))))."
            return out
        }
        out.installed = true
        out.version = Self.firstVersion(v.stdout) ?? Self.firstVersion(v.stderr)

        if id == .codexCli {
            await detectCodex(&out, exe: exe, cwd: cwd)
        } else {
            await detectClaude(&out, exe: exe, cwd: cwd)
            if out.loggedIn != true && isVerified(id) { out.loggedIn = true }
        }
        if out.loggedIn == false {
            out.error = "\(spec.product) is installed but not signed in. Run `\(spec.login)` in a terminal first."
        } else if out.authMethod == "api_key" || out.authMethod == "api_key_helper" {
            out.note = "\(spec.product) is signed in with an API key, so answers are billed to that key, not to a \(spec.plan) subscription."
        }
        out.ready = out.installed && out.loggedIn == true && out.authMethod != "api_key" && out.authMethod != "api_key_helper"
        return out
    }

    private func detectCodex(_ out: inout CLIStatus, exe: String, cwd: String) async {
        let s = await run(.codexCli, exe, ["login", "status"], timeout: Self.probeTimeout, cwd: cwd)
        let text = Self.stripAnsi("\(s.stdout)\n\(s.stderr)")
        if s.code == 0, Rx.test("logged in", text, options: .caseInsensitive), !Rx.test("not logged in", text, options: .caseInsensitive) {
            out.loggedIn = true
            out.authMethod = Rx.test("chatgpt", text, options: .caseInsensitive) ? "chatgpt" : Rx.test("api key", text, options: .caseInsensitive) ? "api_key" : "other"
        } else if Rx.test("not logged in", text, options: .caseInsensitive) || s.code == 1 {
            out.loggedIn = false
        }
    }

    /// `claude auth status`: JSON, exit 0 when signed in, 1 when not. Run only when `claude --help` lists an
    /// `auth` command: an older Claude Code would take "auth status" as a prompt. Without it the answer
    /// stays unknown until the first request.
    private func detectClaude(_ out: inout CLIStatus, exe: String, cwd: String) async {
        let h = await run(.claudeCli, exe, ["--help"], timeout: Self.probeTimeout, cwd: cwd)
        let hasAuth = h.code == 0 && Rx.test("^\\s+auth\\b", Self.stripAnsi(h.stdout), options: .anchorsMatchLines)
        guard hasAuth else { return }
        let s = await run(.claudeCli, exe, ["auth", "status"], timeout: Self.probeTimeout, cwd: cwd)
        if let data = s.stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            out.authMethod = json["authMethod"] as? String
            out.loggedIn = (s.code == 0 && out.authMethod != "none" && (json["loggedIn"] as? Bool) != false)
        } else if s.code == 1, Rx.test("not (logged|signed) in|log ?in", Self.stripAnsi("\(s.stdout)\n\(s.stderr)"), options: .caseInsensitive) {
            out.loggedIn = false
        }
    }
}
