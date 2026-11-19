import SwiftUI
import TessuCore

enum ScanDepth: String, CaseIterable, Identifiable {
    case quick, standard, deep
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var blurb: String {
        switch self {
        case .quick: return "Quick: the router checks only. Fastest."
        case .standard: return "Standard: router checks plus the common service ports."
        case .deep: return "Deep: every check and the widest port sweep. Slowest."
        }
    }
}

enum AlertSensitivity: String, CaseIterable, Identifiable {
    case low, normal, high
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var blurb: String {
        switch self {
        case .low: return "Low: only open backdoors are worth a message."
        case .normal: return "Normal: open backdoors and anything that needs a look."
        case .high: return "High: every change, including new devices and Wi-Fi shifts."
        }
    }
}

/// User preferences, in UserDefaults. Secrets never go here (see Keystore).
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    @Published var scanDepth: ScanDepth { didSet { d.set(scanDepth.rawValue, forKey: "scanDepth") } }
    @Published var alertSensitivity: AlertSensitivity { didSet { d.set(alertSensitivity.rawValue, forKey: "alertSensitivity") } }
    @Published var watchMinutes: Int { didSet { d.set(watchMinutes, forKey: "watchMinutes") } }
    @Published var scanOnOpen: Bool { didSet { d.set(scanOnOpen, forKey: "scanOnOpen") } }
    @Published var advancedEvidence: Bool { didSet { d.set(advancedEvidence, forKey: "advancedEvidence") } }
    @Published var liveRefresh: Bool { didSet { d.set(liveRefresh, forKey: "liveRefresh") } }
    @Published var provider: ProviderID { didSet { d.set(provider.rawValue, forKey: "agentProvider") } }

    init() {
        scanDepth = ScanDepth(rawValue: d.string(forKey: "scanDepth") ?? "") ?? .standard
        alertSensitivity = AlertSensitivity(rawValue: d.string(forKey: "alertSensitivity") ?? "") ?? .normal
        let m = d.integer(forKey: "watchMinutes")
        watchMinutes = m == 0 ? 15 : min(60, max(5, m))
        scanOnOpen = d.object(forKey: "scanOnOpen") as? Bool ?? true
        advancedEvidence = d.bool(forKey: "advancedEvidence")
        liveRefresh = d.object(forKey: "liveRefresh") as? Bool ?? true
        provider = ProviderID(rawValue: d.string(forKey: "agentProvider") ?? "") ?? .claude
    }

    // MARK: history (not secret, but personal: removable from Settings)

    private var speedURL: URL { Self.supportDir.appendingPathComponent("speed-history.json") }
    private var chatURL: URL { Self.supportDir.appendingPathComponent("agent-log.json") }

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Tessu", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func loadSpeedHistory() -> [SpeedResult] {
        guard let data = try? Data(contentsOf: speedURL) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([SpeedResult].self, from: data)) ?? []
    }

    func saveSpeedHistory(_ list: [SpeedResult]) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(list) { try? data.write(to: speedURL, options: .atomic) }
    }

    func loadChat() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: chatURL) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([ChatMessage].self, from: data)) ?? []
    }

    func saveChat(_ list: [ChatMessage]) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(Array(list.suffix(300))) { try? data.write(to: chatURL, options: .atomic) }
    }

    /// "Clear history and preferences": API keys live in the Keychain and are not touched.
    func clearAll() {
        try? FileManager.default.removeItem(at: speedURL)
        try? FileManager.default.removeItem(at: chatURL)
        for k in ["scanDepth", "alertSensitivity", "watchMinutes", "scanOnOpen", "advancedEvidence", "liveRefresh", "agentProvider"] {
            d.removeObject(forKey: k)
        }
        scanDepth = .standard; alertSensitivity = .normal; watchMinutes = 15
        scanOnOpen = true; advancedEvidence = false; liveRefresh = true; provider = .claude
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case me, agent, sys, error }
    var id = UUID()
    var at = Date()
    var provider: ProviderID
    var role: Role
    var text: String
    var model: String?
    var watch = false
}
