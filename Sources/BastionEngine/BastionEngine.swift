// BastionEngine.swift - Main engine entry point

import Foundation

public enum BastionEngine {
    
    // MARK: - Overview
    
    public static func getOverview() async throws -> NetworkOverview {
        return try await SystemInfo.overview()
    }
    
    // MARK: - Devices
    
    public static func getDevices() async throws -> [NetworkDevice] {
        return try await DeviceDiscovery.discoverDevices()
    }
    
    // MARK: - Connections
    
    public static func getConnections() async throws -> [NetworkConnection] {
        return try await ConnectionEngine.getConnections()
    }
    
    // MARK: - Wi-Fi
    
    public static func getWiFiInfo() async -> WiFiInfo {
        return await WiFiEngine.getWiFiInfo()
    }
    
    public static func getWiFiSurvey() async -> WiFiSurvey {
        return await WiFiEngine.getWiFiSurvey()
    }
    
    // MARK: - DNS
    
    public static func getDNSStatus() async -> DNSStatus {
        return await DNSEngine.getStatus()
    }
    
    // MARK: - Speed Test
    
    public static func runSpeedTest() async -> SpeedEngine.SpeedResult {
        return await SpeedEngine.runTest()
    }
    
    // MARK: - Security Scan
    
    public static func runScan() async -> RouterScanner.ScanResult {
        return await RouterScanner.runScan()
    }
}
