import Foundation

public struct NetworkOverview: Codable, Sendable {
    public struct Local: Codable, Sendable {
        public var ip: String
        public var iface: String
        public var mac: String
        public var macRandomized: Bool?
    }
    public struct Gateway: Codable, Sendable {
        public var ip: String?
        public var mac: String?
        public var vendor: String?
    }
    public var hostname: String
    public var local: Local
    public var gateway: Gateway
    public var publicIp: String?
    public var errors: [String]
}

public struct Device: Codable, Hashable, Identifiable, Sendable {
    public var ip: String
    public var mac: String
    public var vendor: String?
    public var randomizedMac: Bool
    public var isGateway: Bool
    public var isThisComputer: Bool
    public var hostname: String?
    public var id: String { ip }
}

public struct DeviceList: Sendable {
    public var devices: [Device]
    public var errors: [String]
}

public struct Connection: Codable, Hashable, Identifiable, Sendable {
    public var process: String?
    public var pid: Int
    public var proto: String
    public var local: String
    public var remoteIp: String
    public var remotePort: Int
    public var state: String?
    public var id: String { "\(proto)|\(pid)|\(local)|\(remoteIp)|\(remotePort)" }
}

public struct ConnectionList: Sendable {
    public var items: [Connection]
    public var errors: [String]
}

public struct DnsStatus: Codable, Sendable {
    public var servers: [String] = []
    public var gatewayIsResolver = false
    /// nil = cannot tell (macOS does not expose whether an encrypted-DNS profile is active).
    public var encrypted: Bool?
    public var provider: String?
    public var note: String?
    public var errors: [String] = []

    public init() {}
}

public struct SpeedResult: Codable, Identifiable, Sendable {
    public var pingMs: Double?
    public var jitterMs: Double?
    public var downMbps: Double?
    public var upMbps: Double?
    public var server = ""
    public var at = Date()
    public var errors: [String] = []
    public var id: Date { at }

    public init() {}

    /// A result counts when anything was measured.
    public var measured: Bool { pingMs != nil || downMbps != nil || upMbps != nil }
}

public enum SpeedPhase: String, Sendable {
    case ping, download, upload, done
}

public struct SpeedProgress: Sendable {
    public var phase: SpeedPhase
    public var mbps: Double?
    public var pingMs: Double?
    /// Overall progress 0...1.
    public var progress: Double
}
