import SwiftUI
import TessuCore

@main
struct TessuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state: AppState
    @StateObject private var location = LocationAuthorizer()

    init() {
        // Carry over what the app stored under its old name, before anything reads its settings.
        // QA snapshot runs skip the Keychain part so they never raise a permission prompt.
        LegacyMigration.runIfNeeded(newSupportDir: Preferences.supportDir, keys: !SnapshotMode.isActive)
        _state = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        WindowGroup("Tessu") {
            RootView()
                .environmentObject(state)
                .environmentObject(location)
                .frame(minWidth: 940, minHeight: 640)
                .task {
                    delegate.state = state
                    location.requestIfNeeded()
                    state.start()
                    await SnapshotMode.run(state)
                }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Network") {
                Button("Scan now") { Task { await state.runScan() } }.keyboardShortcut("r", modifiers: .command)
                Button("Run speed test") { state.selection = .speed; Task { await state.runSpeed() } }.keyboardShortcut("t", modifiers: .command)
                Divider()
                Button("Refresh devices and Wi-Fi") { Task { await state.refresh() } }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu("Go") {
                ForEach(Array(Screen.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.title) { state.selection = s }.keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor weak var state: AppState?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// No Claude Code / Codex run outlives Tessu.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { state?.stop() }
        Agents.shared.shutdown()
    }
}
