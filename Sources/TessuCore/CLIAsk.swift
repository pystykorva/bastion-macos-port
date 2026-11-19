import Foundation

extension CLIRunner {
    /// `model`: "" / "default" -> the CLI's own default.
    public func ask(_ id: ProviderID, model: String, system: String, userText: String, cancel: CancelToken? = nil) async -> AgentAnswer {
        guard let spec = CLILocator.spec(id) else { return .failure("Unknown provider.") }
        let st = await status(id)
        let shown = model.isEmpty ? "default" : model
        guard st.installed, let exe = st.path else {
            return .failure(st.error ?? "\(spec.product) isn't installed. Install it with: \(spec.install)", model: shown)
        }
        if st.loggedIn == false { return .failure(st.error ?? "\(spec.product) is not signed in.", model: shown) }
        let m = (model != "default" && CLILocator.isValidModel(model)) ? model : ""
        let r = id == .claudeCli
            ? await askClaude(exe, model: m, system: system, userText: userText, cancel: cancel)
            : await askCodex(exe, model: m, system: system, userText: userText, version: st.version, cancel: cancel)
        if r.ok { markVerified(id) } else if Rx.test("not signed in", r.error ?? "") { forget(id) }
        return r
    }

    /// Connectivity check.
    public func test(_ id: ProviderID, model: String, cancel: CancelToken? = nil) async -> AgentAnswer {
        _ = await status(id, force: true)
        return await ask(id, model: model, system: "You are a connectivity check. Reply with the single word OK.",
                         userText: "Reply with OK", cancel: cancel)
    }

    func askClaude(_ exe: String, model: String, system: String, userText: String, cancel: CancelToken?) async -> AgentAnswer {
        guard let rd = try? makeRunDir() else { return .failure("Tessu could not create a work folder for Claude Code.", model: model) }
        defer { rd.cleanup() }
        let promptFile = rd.dir.appendingPathComponent("system.txt")
        let settingsFile = rd.dir.appendingPathComponent("settings.json")
        do {
            try Data(system.utf8).write(to: promptFile, options: .atomic)
            try Data(CLIArgs.claudeSettingsJSON.utf8).write(to: settingsFile, options: .atomic)
        } catch { return .failure("Tessu could not prepare the Claude Code run: \(errMsg(error))", model: model) }

        let args = CLIArgs.claude(model: model, settingsFile: settingsFile.path, promptFile: promptFile.path)
        let r = await run(.claudeCli, exe, args, input: userText, timeout: Self.askTimeout, cwd: rd.cwd.path, cancel: cancel)
        return Self.parseClaude(r, requested: model)
    }

    /// The last JSON line of type "result" (or one that has a "result" field), else all of stdout as JSON.
    static func parseClaude(_ r: ExecResult, requested: String) -> AgentAnswer {
        func decode(_ line: String) -> [String: Any]? {
            guard let d = line.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        }
        let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [String: Any]?
        for line in out.split(whereSeparator: \.isNewline).reversed() {
            if let j = decode(String(line)), (j["type"] as? String) == "result" || j["result"] != nil { result = j; break }
        }
        if result == nil { result = decode(out) }
        let used = ((result?["modelUsage"] as? [String: Any])?.keys).map(Array.init) ?? []
        let served = used.first { !Rx.test("haiku", $0, options: .caseInsensitive) } ?? used.first ?? (requested.isEmpty ? "default" : requested)
        guard !r.aborted, !r.timedOut, r.error == nil, let result = result else {
            return .failure(explainFailure(.claudeCli, r), model: served)
        }
        let text = ((result["result"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let subtype = result["subtype"] as? String
        if (result["is_error"] as? Bool) == true || (subtype != nil && subtype != "success") || r.code != 0 {
            return .failure(explainFailure(.claudeCli, r, detail: text.isEmpty ? (subtype ?? "") : text), model: served)
        }
        return AgentAnswer(ok: true, model: served, text: text, error: nil)
    }
}
