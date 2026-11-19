import Foundation

extension CLIRunner {
    /// The model in the user's own ~/.codex/config.toml. Tessu starts Codex with --ignore-user-config (so
    /// the user's MCP servers and tool settings never load), which would also drop their chosen model, so
    /// it is passed back with -m. Top-level keys only.
    static func codexConfiguredModel(home: String = NSHomeDirectory(), env: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let dir = env["CODEX_HOME"] ?? "\(home)/.codex"
        guard let text = try? String(contentsOfFile: "\(dir)/config.toml", encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let l = String(line)
            if Rx.test("^\\s*\\[", l) { break }
            if let m = Rx.first("^\\s*model\\s*=\\s*\"([^\"]+)\"\\s*(#.*)?$", in: l), CLILocator.isValidModel(m[1]) { return m[1] }
        }
        return nil
    }

    /// Reads back the effective feature state with the same overrides `codex exec` gets, once per Codex
    /// binary and version. Returns nil when the command and code runners are confirmed off, or the reason
    /// Tessu refuses to ask. Codex silently ignores feature names it does not know, so the flags alone
    /// prove nothing.
    func codexLockdown(_ exe: String, version: String?, cwd: String, cancel: CancelToken?) async -> String? {
        let key = "\(exe)|\(version ?? "?")"
        if let hit = cachedLockdown(key) { return hit }
        let r = await run(.codexCli, exe, ["features", "list"] + CLIArgs.codexFeatureArgs, timeout: Self.probeTimeout, cwd: cwd, cancel: cancel)
        if r.aborted { return "Cancelled." }
        var state: [String: Bool] = [:]
        for line in Self.stripAnsi(r.stdout).split(whereSeparator: \.isNewline) {
            if let m = Rx.first("^([a-z0-9_]+)\\s+.*?\\s(true|false)\\s*$", in: line.trimmingCharacters(in: .whitespaces)) { state[m[1]] = m[2] == "true" }
        }
        var problem: String?
        if r.code != 0 || state.count < 10 {
            problem = "Tessu could not confirm that this Codex version runs without tools (`codex features list` failed). Update Codex, or use another agent."
        } else {
            var on: [String] = []
            for name in CLIArgs.codexMustBeOff where state[name] != false { on.append(name) }
            for name in CLIArgs.codexFeaturesOff where state[name] == true && !CLIArgs.codexIgnoredState.contains(name) && !on.contains(name) { on.append(name) }
            if !on.isEmpty {
                problem = "This Codex version keeps tools on that Tessu cannot switch off (\(on.joined(separator: ", "))), so it was not asked. Use another agent, or a Codex version Tessu supports."
            }
        }
        storeLockdown(key, problem)
        return problem
    }

    func askCodex(_ exe: String, model: String, system: String, userText: String, version: String?, cancel: CancelToken?) async -> AgentAnswer {
        guard let rd = try? makeRunDir() else { return .failure("Tessu could not create a work folder for Codex.", model: model) }
        defer { rd.cleanup() }
        let useModel = model.isEmpty ? Self.codexConfiguredModel() : model
        let served = useModel ?? "default"
        if let blocked = await codexLockdown(exe, version: version, cwd: rd.cwd.path, cancel: cancel) {
            return .failure(blocked, model: served)
        }
        // `codex exec` has no system-prompt flag that takes text, so Tessu's instructions lead the stdin prompt.
        let input = "<instructions>\n\(system)\n</instructions>\n\n\(userText)"
        let r = await run(.codexCli, exe, CLIArgs.codex(model: useModel), input: input, timeout: Self.askTimeout, cwd: rd.cwd.path, cancel: cancel)
        return Self.parseCodex(r, served: served)
    }

    /// Codex may send commentary agent_messages before the answer, so only the last message of a turn that
    /// completed counts. `error` events also report retries that later succeed, so they only explain a turn
    /// that did not complete.
    static func parseCodex(_ r: ExecResult, served: String) -> AgentAnswer {
        var text = "", failure = "", lastError = ""
        var completed = false
        for line in r.stdout.split(whereSeparator: \.isNewline) {
            guard let d = line.data(using: .utf8), let ev = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            switch ev["type"] as? String {
            case "item.completed":
                if let item = ev["item"] as? [String: Any], item["type"] as? String == "agent_message", let t = item["text"] as? String { text = t }
            case "turn.completed": completed = true
            case "turn.failed": failure = ((ev["error"] as? [String: Any])?["message"] as? String) ?? "the turn failed"
            case "error": if let m = ev["message"] as? String { lastError = m }
            default: break
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.aborted || r.timedOut || r.error != nil { return .failure(explainFailure(.codexCli, r), model: served) }
        if !completed || !failure.isEmpty || r.code != 0 || text.isEmpty {
            let detail = !failure.isEmpty ? failure : (!lastError.isEmpty ? lastError : (completed || !scrub(r.stderr).isEmpty ? "" : "the turn did not finish"))
            return .failure(explainFailure(.codexCli, r, detail: detail), model: served)
        }
        return AgentAnswer(ok: true, model: served, text: text, error: nil)
    }
}
