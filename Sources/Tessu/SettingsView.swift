import SwiftUI
import TessuCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var prefs = Preferences.shared
    @State private var showPreview = false
    @State private var confirmClear = false

    var body: some View {
        Page(title: "Settings", subtitle: "Which AI answers your questions, how Tessu scans, and what stays on this Mac.") {
            EmptyView()
        } content: {
            SubscriptionsCard()
            KeysCard()
            LocalCard()
            scanCard
            privacyCard
            dataCard
        }
        .sheet(isPresented: $showPreview) { PreviewSheet() }
        .confirmationDialog("Clear history and preferences?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { prefs.clearAll(); state.watch.clearLog(); state.speedHistory = []; state.speed = nil }
        } message: { Text("Chat history, speed test history and these preferences are removed. API keys stay in your Keychain.") }
    }

    private var scanCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Scanning and alerts", detail: nil)
                Picker("Scan depth", selection: $prefs.scanDepth) { ForEach(ScanDepth.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented)
                Text(prefs.scanDepth.blurb).font(.caption).foregroundStyle(.secondary)
                Picker("Alert sensitivity", selection: $prefs.alertSensitivity) { ForEach(AlertSensitivity.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented)
                Text(prefs.alertSensitivity.blurb).font(.caption).foregroundStyle(.secondary)
                Stepper(value: $prefs.watchMinutes, in: 5...60, step: 5) { Text("Watch every \(prefs.watchMinutes) minutes") }
                    .onChange(of: prefs.watchMinutes) { _, _ in state.watch.rescheduleAfterIntervalChange() }
                Toggle("Scan when Tessu opens", isOn: $prefs.scanOnOpen)
                Toggle("Keep Wi-Fi, devices and connections fresh while the window is open", isOn: $prefs.liveRefresh)
                Toggle("Show advanced evidence (BSSID, full scan notes, complete evidence text)", isOn: $prefs.advancedEvidence)
            }
        }
    }

    private var privacyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Privacy", detail: nil)
                ForEach(Self.promises, id: \.self) { p in
                    Label(p, systemImage: "checkmark.circle").font(.callout).labelStyle(TopIconLabel())
                }
                Button("Show exactly what an AI would be sent") { showPreview = true }.padding(.top, 4)
            }
        }
    }

    private static let promises = [
        "Scans run on this Mac. Nothing about your network is uploaded unless you ask an AI a question.",
        "Tessu contacts only: Cloudflare for the speed test, ipify.com to learn your public IP, and the AI you choose. Nothing else, and no analytics.",
        "Questions send a snapshot without Wi-Fi names, device names, full MAC addresses, or the last part of your public IP.",
        "API keys are stored in the macOS Keychain, are never shown again and never leave this Mac except to their own provider.",
        "Agents only answer. Tessu never changes a setting on your router or your Mac.",
    ]

    private var dataCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Local data", detail: "Tessu \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                Text("Chat history, speed test history and these preferences are kept on this Mac. API keys are kept in the Keychain and are not affected.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Clear history and preferences", role: .destructive) { confirmClear = true }
                    Button("Show data folder") { NSWorkspace.shared.activateFileViewerSelecting([Preferences.supportDir]) }
                }
            }
        }
    }
}

struct TopIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(Theme.color(.ok))
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PreviewSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = state.agents.preview(state.snapshot(), compact: Preferences.shared.provider == .local)
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("What an AI is sent").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            Text("This is the exact snapshot and system prompt that go with every question. Nothing leaves your Mac when you open this window.")
                .font(.callout).foregroundStyle(.secondary)
            TabView {
                ScrollView { Text(p.snapshot).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
                    .tabItem { Text("Snapshot") }
                ScrollView { Text(p.system).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
                    .tabItem { Text("System prompt") }
            }
        }
        .padding(20).frame(width: 720, height: 560)
    }
}
