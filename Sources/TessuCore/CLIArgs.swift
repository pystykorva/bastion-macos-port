import Foundation

/// The exact argv for each subscription CLI. Safety rules (docs/CONTRACT.md of the original project):
///  - the question and snapshot go to the CLI on stdin, never in argv;
///  - argv holds only fixed flags, a validated model id and paths Tessu created itself;
///  - every tool the CLI has is switched off or denied, and the run happens in an empty directory,
///    so the model can only answer in text.
public enum CLIArgs {
    /// Codex features that give the model a way to act (run commands, run JS, browse, use apps, spawn
    /// agents, run hooks). Passed as `-c features.<name>=false`.
    public static let codexFeaturesOff = [
        "shell_tool", "unified_exec", "apps", "plugins", "hooks", "browser_use", "browser_use_external",
        "browser_use_full_cdp_access", "computer_use", "in_app_browser", "in_app_local_automation",
        "image_generation", "multi_agent", "multi_agent_v2", "view_image", "code_mode", "code_mode_host",
        "sleep_tool", "goals", "tool_suggest", "skill_search", "request_permissions_tool", "memories",
    ]
    /// Must be listed by `codex features list` and report false, or Tessu refuses to ask: these are the
    /// switches that give the model a command or code runner.
    public static let codexMustBeOff = ["shell_tool", "code_mode_host"]
    /// Listed above but not switchable by config on Codex 0.153.4 (`features list` keeps showing true). It
    /// only picks which shell tool is offered when shell_tool is on; with shell_tool off no exec tool exists.
    public static let codexIgnoredState: Set<String> = ["unified_exec"]

    public static var codexFeatureArgs: [String] { codexFeaturesOff.flatMap { ["-c", "features.\($0)=false"] } }

    /// `claude -p` with no tools, no MCP, no hooks, no session, Tessu's own system prompt.
    /// Not `--bare`: bare mode never reads the subscription (OAuth) login.
    public static func claude(model: String?, settingsFile: String, promptFile: String) -> [String] {
        var args = [
            "-p",
            "--output-format", "json",
            "--tools", "",
            "--disallowedTools", "*",
            "--strict-mcp-config",
            "--permission-mode", "dontAsk",
            "--setting-sources", "project",
            "--settings", settingsFile,
            "--disable-slash-commands",
            "--no-session-persistence",
            "--system-prompt-file", promptFile,
        ]
        if let m = model, !m.isEmpty { args += ["--model", m] }
        return args
    }

    /// `codex exec` read-only, approvals never, no web search, user config and rules ignored, prompt on stdin.
    public static func codex(model: String?) -> [String] {
        var args = [
            "exec", "--json", "--color", "never", "--skip-git-repo-check", "--ephemeral",
            "--ignore-user-config", "--ignore-rules", "--sandbox", "read-only",
            "-c", "approval_policy=never", "-c", "web_search=disabled",
        ] + codexFeatureArgs
        if let m = model, !m.isEmpty { args += ["-m", m] }
        args.append("-")
        return args
    }

    /// Settings file for Claude Code: hooks are shell commands and are not tools, so the tool flags above do
    /// not stop them. `--setting-sources project` skips the user's settings; this adds disableAllHooks.
    public static let claudeSettingsJSON = "{\"disableAllHooks\":true}"
}
