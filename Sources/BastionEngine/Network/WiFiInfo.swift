// WiFiInfo.swift - Wi-Fi information and channel survey

import Foundation

enum WiFiEngine {
    
    // MARK: - Current Wi-Fi Info
    
    static func getWiFiInfo() async -> WiFiInfo {
        var info = WiFiInfo()
        
        do {
            let result = try runCommand("system_profiler", ["SPAirPortDataType", "-json"])
            
            if let data = result.stdout.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let networks = json.first?["_networks"] as? [[String: Any]],
               let current = networks.first(where: { ($0["ssid"] as? String ?? "") == info.ssid }) {
                // Try to find the current network in the list
            }
            
            // Parse system_profiler output for current connection
            let lines = result.stdout.split(separator: "\n")
            var inCurrentNetwork = false
            
            for line in lines {
                let lineStr = String(line)
                
                if lineStr.contains("\"ssid\"") || lineStr.contains("SSID:") {
                    inCurrentNetwork = true
                }
                
                if let ssidMatch = lineStr.range(of: "\"ssid\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                    info.ssid = String(lineStr[ssidMatch]).replacingOccurrences(of: "\"ssid\" : \"", with: "")
                        .replacingOccurrences(of: "\"ssid\":\"", with: "")
                }
                
                if let bssidMatch = lineStr.range(of: "\"bssid\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                    info.bssid = String(lineStr[bssidMatch]).replacingOccurrences(of: "\"bssid\" : \"", with: "")
                        .replacingOccurrences(of: "\"bssid\":\"", with: "")
                }
                
                if let channelMatch = lineStr.range(of: "\"channel\"\\s*:\\s*(\\d+)", options: .regularExpression) {
                    info.channel = Int(String(lineStr[channelMatch]).replacingOccurrences(of: "\"channel\" : ", with: ""))
                }
                
                if let bandMatch = lineStr.range(of: "\"band\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                    let bandStr = String(lineStr[bandMatch]).replacingOccurrences(of: "\"band\" : \"", with: "")
                    if bandStr.contains("5") { info.band = "5" }
                    else if bandStr.contains("6") { info.band = "6" }
                    else { info.band = "2.4" }
                }
                
                if let rssiMatch = lineStr.range(of: "\"rssi\"\\s*:\\s*(-?\\d+)", options: .regularExpression) {
                    info.rssi = Int(String(lineStr[rssiMatch]).replacingOccurrences(of: "\"rssi\" : ", with: ""))
                    info.signalPercent = rssiToPercent(info.rssi!)
                }
                
                if let securityMatch = lineStr.range(of: "\"security_type\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                    info.security = String(lineStr[securityMatch]).replacingOccurrences(of: "\"security_type\" : \"", with: "")
                }
            }
            
        } catch {
            // Wi-Fi not available (e.g., on a Mac with only Ethernet)
        }
        
        return info
    }
    
    // MARK: - Wi-Fi Survey (nearby networks)
    
    static func getWiFiSurvey() async -> WiFiSurvey {
        var survey = WiFiSurvey()
        
        do {
            let result = try runCommand("system_profiler", ["SPAirPortDataType", "-json"])
            
            if let data = result.stdout.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let networks = json.first?["_networks"] as? [[String: Any]] {
                
                for net in networks {
                    let ssid = (net["ssid"] as? String) ?? ""
                    guard !ssid.isEmpty else { continue }
                    
                    let bssid = net["bssid"] as? String
                    var channel: Int = 0
                    if let ch = net["channel"] as? Double { channel = Int(ch) }
                    
                    var band: String = "2.4"
                    if let bandStr = net["band"] as? String {
                        if bandStr.contains("5") { band = "5" }
                        else if bandStr.contains("6") { band = "6" }
                    }
                    
                    var rssi: Int?
                    if let rssiVal = net["rssi"] as? Double { rssi = Int(rssiVal) }
                    
                    let signalPercent = rssi.map { rssiToPercent($0) }
                    
                    survey.networks.append(WiFiNetwork(
                        ssid: ssid,
                        bssid: bssid,
                        channel: channel,
                        band: band,
                        signalPercent: signalPercent,
                        rssi: rssi
                    ))
                }
                
                // Sort by signal strength
                survey.networks.sort { (a, b) in
                    (a.signalPercent ?? 0) > (b.signalPercent ?? 0)
                }
            }
            
        } catch {
            // Survey not available
        }
        
        return survey
    }
    
    // MARK: - Helpers
    
    private static func rssiToPercent(_ rssi: Int) -> Int {
        // Typical range: -100 (no signal) to -30 (excellent)
        let percent = min(100, max(0, (rssi + 100) * 100 / 70))
        return percent
    }
}
