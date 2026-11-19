// Models.swift - Data models for Bastion network engine

import Foundation

// MARK: - Overview

struct NetworkOverview {
    var hostname: String = ""
    var localIP: String = ""
    var localInterface: String = ""
    var localMAC: String = ""
    var gatewayIP: String?
    var gatewayMAC: String?
    var gatewayVendor: String?
    var publicIP: String?
}

// MARK: - Device

struct NetworkDevice {
    var ip: String
    var mac: String?
    var vendor: String?
    var hostname: String?
    var isGateway: Bool = false
    var isThisComputer: Bool = false
    var randomizedMAC: Bool = false
}

// MARK: - Connection

struct NetworkConnection {
    var processName: String?
    var pid: Int32?
    var protocolType: String // "tcp" or "udp"
    var localAddress: String
    var remoteIP: String?
    var remotePort: Int?
    var state: String? // "ESTABLISHED", "LISTEN" for TCP
}

// MARK: - Wi-Fi

struct WiFiInfo {
    var ssid: String?
    var bssid: String?
    var band: String? // "2.4", "5", "6"
    var channel: Int?
    var widthMHz: Int?
    var rssi: Int?
    var signalPercent: Int? // 0-100
    var security: String?
}

struct WiFiNetwork {
    var ssid: String
    var bssid: String?
    var channel: Int
    var band: String // "2.4", "5", "6"
    var signalPercent: Int?
    var rssi: Int?
    var isOwn: Bool = false
}

struct WiFiSurvey {
    var networks: [WiFiNetwork] = []
    var currentChannel: Int?
    var currentBand: String?
    var recommendation: WiFiRecommendation?
}

struct WiFiRecommendation {
    var channel: Int
    var band: String
    var reason: String
}

// MARK: - DNS

struct DNSStatus {
    var servers: [String] = []
    var encrypted: Bool? // nil = unknown
    var provider: String?
    var gatewayIsResolver: Bool = false
}

// MARK: - Speed Test

struct SpeedResult {
    var pingMs: Double?
    var jitterMs: Double?
    var downloadMbps: Double?
    var uploadMbps: Double?
    var server: String = "Cloudflare"
}

// MARK: - Scan Check

struct ScanCheck {
    enum Status { case ok, warn, risk, unknown }
    enum Severity { case critical, high, medium, low, info }
    
    var id: String
    var title: String
    var status: Status
    var severity: Severity
    var evidence: String
    var fixDescription: String?
}

struct ScanResult {
    var score: Int // 0-100
    var checks: [ScanCheck] = []
    var openPorts: [(port: Int, service: String)] = []
    var upnpMappings: [UPnPMapping] = []
}

struct UPnPMapping {
    var protocol: String
    var externalPort: Int
    var internalClient: String
    var internalPort: Int
    var description: String
}

// MARK: - Progress

struct ScanProgress {
    var index: Int
    var total: Int
    var id: String?
    var title: String?
    var status: ScanCheck.Status?
}

struct SpeedProgress {
    enum Phase { case ping, download, upload, done }
    var phase: Phase
    var progress: Double // 0-1 within phase
}
