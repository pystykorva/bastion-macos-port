import SwiftUI
import TessuCore

/// Everything the app knows about the network right now. One source of truth for every view; each piece
/// is nil until measured, and nil always means "not measured", never zero.
@MainActor
final class AppState: ObservableObject {
    @Published var selection: Screen = .home
    /// Providers with a question in flight (typing indicator, Send becomes Stop).
    @Published var asking: Set<ProviderID> = []

    @Published var overview: NetworkOverview?
    @Published var scan: ScanReport?
    @Published var scanProgress: [String: ScanProgress] = [:]
    @Published var scanning = false
    @Published var scanError: String?

    @Published var devices: DeviceList?
    @Published var connections: ConnectionList?
    @Published var wifi: WifiInfo?
    @Published var survey: WifiSurvey?
    @Published var dns: DnsStatus?

    @Published var speed: SpeedResult?
    @Published var speedHistory: [SpeedResult] = []
    @Published var speedRunning = false
    @Published var speedProgress: SpeedProgress?
    var speedToken: CancelToken?

    @Published var providers: [ProviderInfo] = []
    @Published var toast: Toast?

    let agents = Agents.shared
    let prefs = Preferences.shared
    private(set) lazy var watch = WatchMode(state: self)
    private var refreshTimer: Timer?
    private var lastLoaded: [String: Date] = [:]

    struct Toast: Identifiable, Equatable {
        enum Kind { case info, warn, error }
        let id = UUID()
        var text: String
        var kind: Kind
    }

    func show(_ text: String, _ kind: Toast.Kind = .info) {
        let t = Toast(text: text, kind: kind)
        toast = t
        Task { try? await Task.sleep(nanoseconds: 5_000_000_000); if toast?.id == t.id { toast = nil } }
    }

    /// What the AI is shown (after PromptBuilder minimizes it).
    func snapshot() -> SnapshotInput {
        SnapshotInput(overview: overview, scan: scan, wifi: wifi, survey: survey, dns: dns, speed: speed,
                      devices: devices?.devices, connections: connections?.items)
    }

    // MARK: lifecycle

    func start() {
        speedHistory = prefs.loadSpeedHistory()
        speed = speedHistory.first
        Task {
            await load(.overview)
            if prefs.scanOnOpen { await runScan() }
        }
        Task { await loadAll(except: [.overview]) }
        Task { await loadProviders() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        agents.shutdown()
        speedToken?.cancel()
    }

    // MARK: live feeds

    enum Feed: String, CaseIterable { case overview, wifi, connections, devices, dns, survey }

    /// How often each feed refreshes while the window is open. Intervals are per data source.
    static let intervals: [Feed: TimeInterval] = [.wifi: 15, .connections: 20, .devices: 90, .overview: 120, .dns: 120, .survey: 300]

    private func tick() {
        guard NSApp.isActive, prefs.liveRefresh else { return }
        let now = Date()
        for (feed, every) in Self.intervals {
            if let last = lastLoaded[feed.rawValue], now.timeIntervalSince(last) >= every { Task { await load(feed) } }
        }
    }

    func load(_ feed: Feed) async {
        switch feed {
        case .overview: overview = await Overview.overview()
        case .wifi: wifi = await Wifi.info()
        case .connections: connections = await Connections.list()
        case .devices: devices = await Devices.discover()
        case .dns: dns = await Dns.status()
        case .survey: survey = await Wifi.survey()
        }
        lastLoaded[feed.rawValue] = Date()
    }

    func loadAll(except: Set<Feed> = []) async {
        await withTaskGroup(of: Void.self) { group in
            for f in Feed.allCases where !except.contains(f) { group.addTask { @MainActor in await self.load(f) } }
        }
    }

    /// Re-reads everything (watch mode and the Refresh buttons).
    func refresh() async { await loadAll() }

    func loadProviders(refresh: Bool = false) async {
        providers = await agents.providers(refresh: refresh)
    }
}
