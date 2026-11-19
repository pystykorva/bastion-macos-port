import Foundation

// Data shapes shared by the engine, the agents and the app. They mirror docs/CONTRACT.md of the
// original project. Anything a measurement could not determine is nil, never a made-up zero.

public enum CheckStatus: String, Codable, Sendable, CaseIterable {
    case ok, warn, risk, unknown

    /// Sort order for "what needs attention first".
    public var rank: Int {
        switch self {
        case .risk: return 0
        case .warn: return 1
        case .unknown: return 2
        case .ok: return 3
        }
    }
}

public enum Severity: String, Codable, Sendable {
    case critical, high, medium, low, info

    public var weight: Int {
        switch self {
        case .critical: return 30
        case .high: return 15
        case .medium: return 8
        case .low: return 3
        case .info: return 0
        }
    }

    public var rank: Int {
        switch self {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        case .info: return 4
        }
    }
}

/// What a guided fix's "open" button opens. Tessu never changes a setting itself.
public enum FixTarget: String, Codable, Sendable {
    case routerAdmin = "router-admin"
    case dnsSettings = "dns-settings"
    case wifiSettings = "wifi-settings"
    case macPrivacy = "mac-privacy"
}

public struct Fix: Codable, Hashable, Sendable {
    public var label: String
    public var steps: [String]
    public var open: FixTarget?
}

public struct CheckResult: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var status: CheckStatus
    public var severity: Severity
    public var evidence: String
    public var fix: Fix?
}

public struct UpnpMapping: Codable, Hashable, Sendable {
    public var proto: String
    public var externalPort: Int
    public var internalClient: String
    public var internalPort: Int?
    public var description: String
}

public struct OpenPort: Codable, Hashable, Sendable {
    public var port: Int
    public var service: String
}

public struct ScanReport: Codable, Sendable {
    public var startedAt: Date
    public var finishedAt: Date
    public var score: Int
    public var checks: [CheckResult]
    public var upnpMappings: [UpnpMapping]
    public var openPorts: [OpenPort]
    public var errors: [String]
}

public struct ScanProgress: Sendable {
    public var index: Int
    public var total: Int
    public var id: String
    public var title: String
    /// nil while the check is running, set once it finished.
    public var status: CheckStatus?
}
