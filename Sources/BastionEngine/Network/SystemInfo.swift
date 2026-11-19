// SystemInfo.swift - Network overview, default route, gateway info

import Foundation

enum SystemInfo {
    
    // MARK: - Default Route
    
    static func defaultRoute() async throws -> (gateway: String, interface: String, localIP: String) {
        let result = try runCommand("route", ["-n", "get", "default"])
        
        var gateway = ""
        var interface = ""
        var localIP = ""
        
        for line in result.stdout.split(separator: "\n") {
            let line = String(line).trimmingCharacters(in: .whitespaces)
            
            if line.hasPrefix("gateway: ") {
                gateway = String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("interface: ") {
                interface = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("local address: ") {
                localIP = String(line.dropFirst(15)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("local ") {
                let parts = String(line).split(separator: ":")
                if parts.count >= 2 {
                    let val = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    if !localIP.isEmpty, val.contains(".") {
                        localIP = val
                    }
                }
            }
        }
        
        guard !gateway.isEmpty else {
            throw SystemError.invalidOutput("No gateway found in route output")
        }
        
        return (gateway, interface, localIP)
    }
    
    // MARK: - Overview
    
    static func overview() async throws -> NetworkOverview {
        let hostname = ProcessInfo.processInfo.hostName
        
        var overview = NetworkOverview(hostname: hostname)
        
        // Get default route info
        let route = try Self.defaultRoute()
        overview.localIP = route.localIP
        overview.localInterface = route.interface
        overview.gatewayIP = route.gateway
        
        // Get local MAC from ifconfig
        let ifconfigResult = try runCommand("ifconfig", [route.interface])
        if let macMatch = ifconfigResult.stdout.range(of: "ether \\b[0-9a-f]{12}\\b", options: .regularExpression) {
            let macStr = String(ifconfigResult.stdout[macMatch]).replacingOccurrences(of: "ether ", with: "")
            overview.localMAC = macStr
        }
        
        // Get gateway MAC from ARP
        let arpResult = try runCommand("arp", ["-an"])
        for line in arpResult.stdout.split(separator: "\n") {
            let lineStr = String(line)
            if lineStr.contains("(\(route.gateway))") {
                if let macMatch = lineStr.range(of: "at ([0-9a-f:]{17})", options: .regularExpression) {
                    let macStr = String(lineStr[macMatch]).replacingOccurrences(of: "at ", with: "")
                    overview.gatewayMAC = normalizeMAC(macStr) ?? macStr
                }
            }
        }
        
        if let gatewayMAC = overview.gatewayMAC {
            overview.gatewayVendor = lookupVendor(mac: gatewayMAC)
        }
        
        // Get public IP (best-effort, non-critical)
        do {
            let url = URL(string: "https://api.ipify.org?format=json")!
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ip = json["ip"] as? String {
                overview.publicIP = ip
            }
        } catch {
            // Non-critical, leave publicIP as nil
        }
        
        return overview
    }
}
