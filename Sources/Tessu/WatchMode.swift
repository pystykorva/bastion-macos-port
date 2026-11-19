import SwiftUI
import TessuCore

/// Every few minutes: refresh the network, find what changed, and only if something above the alert
/// sensitivity changed, ask the AI about it. Runs only while Tessu is open, and lives here (not in a
/// view) so it keeps going while the user looks at other screens. Agents only answer; they never act.
@MainActor
final class WatchMode: ObservableObject {
    @Published private(set) var on = false
    @Published private(set) var running = false
    @Published private(set) var nextAt: Date?
    @Published private(set) var lastAt: Date?
    @Published var log: [ChatMessage]

    private unowned let state: AppState
    private var timer: Timer?
    private var previous: WatchSnapshot?
    static let retryAfter: TimeInterval = 60

    init(state: AppState) {
        self.state = state
        self.log = Preferences.shared.loadChat()
    }

    // MARK: chat log shared with the Agents screen

    func append(_ provider: ProviderID, _ role: ChatMessage.Role, _ text: String, model: String? = nil, watch: Bool = false) {
        log.append(ChatMessage(provider: provider, role: role, text: text, model: model, watch: watch))
        if log.count > 300 { log.removeFirst(log.count - 300) }
        state.prefs.saveChat(log)
    }

    func clearLog() { log = []; state.prefs.saveChat([]) }

    // MARK: switch

    func set(_ enabled: Bool) {
        on = enabled
        let id = state.prefs.provider
        if enabled {
            previous = WatchSnapshot.capture(state)
            append(id, .sys, "Watch mode on. Every \(state.prefs.watchMinutes) minutes Tessu refreshes the network and asks \(id.name) about anything that changed. Only while Tessu is open.", watch: true)
        } else {
            previous = nil
            append(id, .sys, "Watch mode off.", watch: true)
        }
        schedule()
    }

    func rescheduleAfterIntervalChange() { if on && !running { schedule() } }

    private func schedule(after delay: TimeInterval? = nil) {
        timer?.invalidate(); timer = nil
        guard on else { nextAt = nil; return }
        let seconds = delay ?? TimeInterval(state.prefs.watchMinutes * 60)
        nextAt = Date().addingTimeInterval(seconds)
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    // MARK: one check

    func tick() async {
        timer = nil
        guard on, !running else { return }
        let id = state.prefs.provider
        running = true
        var retry: TimeInterval?
        defer { running = false; lastAt = Date(); schedule(after: retry) }

        let before = previous ?? WatchSnapshot.capture(state)
        await state.refresh()
        await state.runScan()
        let after = WatchSnapshot.capture(state)
        previous = after

        let all = WatchDiff.changes(from: before, to: after)
        let items = WatchDiff.filter(all, state.prefs.alertSensitivity)
        let since = Self.clock(before.at)
        guard !items.isEmpty else {
            append(id, .sys, "Watch check: nothing \(all.isEmpty ? "" : "above your alert sensitivity ")changed since \(since). Agent not asked.", watch: true)
            return
        }
        append(id, .sys, "Watch check found \(items.count) change\(items.count == 1 ? "" : "s") since \(since):\n" + items.map { "- \($0.text)" }.joined(separator: "\n"), watch: true)

        if state.agents.isBusy(id) {
            // Keep the old baseline so the retry reports these changes instead of losing them.
            previous = before
            retry = Self.retryAfter
            append(id, .sys, "\(id.name) is still answering another question, so these changes were not sent yet. Tessu will check again in a minute.", watch: true)
            return
        }
        if let info = state.providers.first(where: { $0.id == id }), !info.hasKey {
            append(id, .error, "The agent was not asked. " + Chat.notReadyText(id, info), watch: true)
            return
        }
        let q = "Watch mode check. Tessu refreshed my network and found these changes since \(since):\n" +
            items.map { "- \($0.text)" }.joined(separator: "\n") +
            "\nUsing the attached snapshot, tell me in at most four short sentences what changed and whether any of it needs my attention. " +
            "You cannot take actions; only suggest what I could do. If none of it matters, say so in one sentence."
        let result = await Chat.ask(state, id, q, silentQuestion: true, watch: true)
        if result == .busy { previous = before; retry = Self.retryAfter }
    }

    static func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}
