import Foundation

public enum WifiBand: String, Codable, Sendable, Comparable {
    case ghz24 = "2.4"
    case ghz5 = "5"
    case ghz6 = "6"

    public var label: String { rawValue + " GHz" }
    public static func < (a: WifiBand, b: WifiBand) -> Bool {
        a.rawValue.compare(b.rawValue, options: .numeric) == .orderedAscending
    }
}

public struct WifiInfo: Codable, Sendable {
    public var supported = false
    public var ssid: String?
    public var bssid: String?
    public var band: WifiBand?
    public var channel: Int?
    public var widthMHz: Int?
    public var rssi: Int?
    public var signalPct: Int?
    public var rxMbps: Double?
    public var txMbps: Double?
    public var security: String?
    public var nomap: Bool?
    public var errors: [String] = []

    public init() {}
}

public struct WifiNetwork: Codable, Hashable, Identifiable, Sendable {
    public var ssid: String
    public var bssid: String?
    public var channel: Int
    public var band: WifiBand
    public var signalPct: Int?
    public var rssi: Int?
    public var widthMHz: Int?
    /// The user's own router (connected access point or a sibling radio); not a competing neighbour.
    public var own = false
    public var id: String { bssid ?? "\(ssid)|\(band.rawValue)|\(channel)|\(own ? "own" : String(rssi ?? 0))" }

    public init(ssid: String, bssid: String?, channel: Int, band: WifiBand, signalPct: Int?, rssi: Int?, widthMHz: Int?, own: Bool = false) {
        self.ssid = ssid; self.bssid = bssid; self.channel = channel; self.band = band
        self.signalPct = signalPct; self.rssi = rssi; self.widthMHz = widthMHz; self.own = own
    }
}

public struct CongestionEntry: Codable, Hashable, Sendable {
    public var channel: Int
    public var band: WifiBand
    public var count: Int
}

public struct ChannelRecommendation: Codable, Hashable, Sendable {
    public var channel: Int
    public var band: WifiBand
    public var reason: String
    public var neighboursNow: Int
    public var neighboursThere: Int
}

public struct WifiSurvey: Codable, Sendable {
    public var supported = false
    public var networks: [WifiNetwork] = []
    public var congestion: [CongestionEntry] = []
    public var currentChannel: Int?
    public var currentBand: WifiBand?
    public var recommendation: ChannelRecommendation?
    public var errors: [String] = []

    public init() {}
}

/// Typed stand-in for the original renderer's snapshot(): what the app knows right now.
/// Everything sent to an AI provider goes through PromptBuilder, which minimizes it.
public struct SnapshotInput: Sendable {
    public var overview: NetworkOverview?
    public var scan: ScanReport?
    public var wifi: WifiInfo?
    public var survey: WifiSurvey?
    public var dns: DnsStatus?
    public var speed: SpeedResult?
    public var devices: [Device]?
    public var connections: [Connection]?

    public init(overview: NetworkOverview? = nil, scan: ScanReport? = nil, wifi: WifiInfo? = nil,
                survey: WifiSurvey? = nil, dns: DnsStatus? = nil, speed: SpeedResult? = nil,
                devices: [Device]? = nil, connections: [Connection]? = nil) {
        self.overview = overview; self.scan = scan; self.wifi = wifi; self.survey = survey
        self.dns = dns; self.speed = speed; self.devices = devices; self.connections = connections
    }
}
