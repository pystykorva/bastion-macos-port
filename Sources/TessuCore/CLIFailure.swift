import Foundation

extension CLIRunner {
    /// Plain-sentence reason a CLI run failed.
    static func explainFailure(_ id: ProviderID, _ r: ExecResult, detail: String = "") -> String {
        guard let spec = CLILocator.spec(id) else { return "Unknown provider." }
        if r.aborted { return "Cancelled." }
        if r.timedOut { return "\(spec.product) did not answer within \(Int(askTimeout)) seconds. Try again, or pick a faster model." }
        if let e = r.error { return "Could not start \(spec.product): \(scrub(e))" }
        let text = "\(detail) \(r.stderr) \(r.stdout)"
        if Rx.test("not (logged|signed) in|please (log|sign) in|unauthori[sz]ed|\\b401\\b|invalid (api key|token|credentials)|authentication|login required|/login", text, options: .caseInsensitive) {
            return "\(spec.product) is not signed in. Run `\(spec.login)` in a terminal, then try again."
        }
        if Rx.test("usage limit|rate limit|quota|too many requests|\\b429\\b|limit reached|hit your limit", text, options: .caseInsensitive) {
            return "Your \(spec.plan) plan's usage limit was reached. Wait for it to reset, or use an API key instead."
        }
        if Rx.test("model", text, options: .caseInsensitive),
           Rx.test("(not found|not supported|does not exist|invalid|unknown|not available)", text, options: .caseInsensitive) {
            return "\(spec.product) rejected that model. Pick another one in Settings, or \"default\"."
        }
        let msg = scrub(detail.isEmpty ? (r.stderr.isEmpty ? r.stdout : r.stderr) : detail)
        return msg.isEmpty
            ? "\(spec.product) exited with code \(r.code.map(String.init) ?? "?") and no answer."
            : "\(spec.product) failed: \(msg)"
    }

    /// One line, no colour codes, no keys, at most 400 characters.
    static func scrub(_ text: String) -> String {
        let s = stripAnsi(text)
            .replacingOccurrences(of: "\\b(sk-ant-|sk-|xai-)[A-Za-z0-9_\\-*]{4,}", with: "[key]", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return String(s.prefix(400))
    }
}
