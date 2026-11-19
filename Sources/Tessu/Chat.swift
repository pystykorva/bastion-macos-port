import SwiftUI
import TessuCore

/// Asking an agent. Kept out of the views so both the Agents screen, the Home bar and watch mode use it.
@MainActor
enum Chat {
    enum Outcome { case empty, busy, done }

    /// Why a provider cannot answer yet, in plain words.
    static func notReadyText(_ id: ProviderID, _ info: ProviderInfo?) -> String {
        guard id.isCLI else { return "No \(id.name) key saved. Add one in Settings." }
        let product = CLILocator.spec(id)?.product ?? "The CLI"
        guard info?.cli?.installed == true else { return "\(product) is not installed on this computer. Settings shows how to install it." }
        return "\(product) is not signed in. Run `\(CLILocator.spec(id)?.login ?? "login")` in a terminal, then try again."
    }

    /// Providers a person can use right now, best first: ready subscriptions, then API keys, then
    /// subscriptions whose sign-in is unchecked. Subscriptions that are not installed are hidden.
    static func usable(_ list: [ProviderInfo]) -> [ProviderInfo] {
        let visible = list.filter { !$0.id.isCLI || $0.cli?.installed == true }
        func rank(_ p: ProviderInfo) -> Int {
            if p.id.isCLI { return p.cli?.ready == true ? 0 : 2 }
            return 1
        }
        return visible.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// "Auto" picks a ready subscription, then the first API provider with a key, then a usable but
    /// unchecked subscription.
    static func auto(_ list: [ProviderInfo]) -> ProviderID? {
        list.first { $0.id.isCLI && $0.cli?.ready == true }?.id
            ?? list.first { !$0.id.isCLI && $0.hasKey }?.id
            ?? list.first { $0.id.isCLI && $0.hasKey }?.id
    }

    @discardableResult
    static func ask(_ s: AppState, _ id: ProviderID, _ question: String, silentQuestion: Bool = false, watch: Bool = false) async -> Outcome {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return .empty }
        if s.agents.isBusy(id) { return .busy }
        if !silentQuestion { s.watch.append(id, .me, q) }
        s.asking.insert(id)
        let answer = await s.agents.ask(id, question: q, snapshot: s.snapshot())
        s.asking.remove(id)
        if answer.ok, !answer.text.isEmpty {
            s.watch.append(id, .agent, answer.text, model: answer.model, watch: watch)
        } else {
            let msg = answer.error ?? (answer.ok ? "The model returned an empty answer." : "No answer.")
            s.watch.append(id, .error, msg, model: answer.model.isEmpty ? nil : answer.model, watch: watch)
        }
        return .done
    }
}
