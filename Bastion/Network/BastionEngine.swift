// BastionEngine.swift - Main engine entry point

import Foundation

enum BastionEngine {
    
    // MARK: - Overview
    
    static func getOverview() async throws -> NetworkOverview {
        return try await SystemInfo.overview()
    }
    
    // MARK: - Devices
    
    static func getDevices() async throws -> [NetworkDevice] {
        return try await DeviceDiscovery.discoverDevices()
    }
    
    // MARK: - Connections
    
    static func getConnections() async throws -> [NetworkConnection] {
        return try await ConnectionEngine.getConnections()
    }
    
    // MARK: - Wi-Fi
    
    static func getWiFiInfo() async -> WiFiInfo {
        return await WiFiEngine.getWiFiInfo()
    }
    
    static func getWiFiSurvey() async -> WiFiSurvey {
        return await WiFiEngine.getWiFiSurvey()
    }
    
    // MARK: - DNS
    
    static func getDNSStatus() async -> DNSStatus {
        return await DNSEngine.getStatus()
    }
    
    // MARK: - Speed Test
    
    static func runSpeedTest() async -> SpeedEngine.SpeedResult {
        return await SpeedEngine.runTest()
    }
    
    // MARK: - Security Scan
    
    static func runScan() async -> RouterScanner.ScanResult {
        return await RouterScanner.runScan()
    }
}
