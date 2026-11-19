// DeviceDiscovery.swift - ARP table reading and device discovery

import Foundation

enum DeviceDiscovery {
    
    // MARK: - ARP Table
    
    static func readArp() async throws -> [NetworkDevice] {
        let result = try runCommand("arp", ["-an"])
        
        var devices: [NetworkDevice] = []
        var seenIPs = Set<String>()
        
        for line in result.stdout.split(separator: "\n") {
            let lineStr = String(line).trimmingCharacters(in: .whitespaces)
            
            // Format: ? (192.168.1.1) at a:b:c:d:e:f on en0 ifscope [ethernet]
            guard let ipMatch = lineStr.range(of: "\\(([0-9.]+)\\)", options: .regularExpression),
                  let macMatch = lineStr.range(of: "at ([0-9a-f:]+)", options: .regularExpression) else {
                continue
            }
            
            let ip = String(lineStr[ipMatch]).replacingOccurrences(of: "(", with: "")
            let macRaw = String(lineStr[macMatch]).replacingOccurrences(of: "at ", with: "")
            
            guard macRaw != "(incomplete)" else { continue }
            if ip.hasSuffix(".255") { continue }
            
            let mac = normalizeMAC(macRaw) ?? macRaw
            if mac.replacingOccurrences(of: ":", with: "").lowercased() == "ffffffffffff" { continue }
            
            if seenIPs.contains(ip) { continue }
            seenIPs.insert(ip)
            
            devices.append(NetworkDevice(
                ip: ip,
                mac: mac,
                vendor: lookupVendor(mac: mac),
                randomizedMAC: isRandomizedMAC(mac)
            ))
        }
        
        return devices
    }
    
    // MARK: - Reverse DNS
    
    static func reverseDNS(for ips: [String], gateway: String?) async -> [String: String] {
        var names: [String: String] = [:]
        
        // Use system DNS servers, but only if they're local
        var dnsServers: [String] = []
        do {
            let scutilResult = try runCommand("scutil", ["--dns"])
            let lines = scutilResult.stdout.split(separator: "\n")
            var inResolver1 = false
            
            for line in lines {
                let lineStr = String(line)
                if lineStr.hasPrefix("Resolver #1") || lineStr == "resolver #1" {
                    inResolver1 = true
                } else if inResolver1 && lineStr.hasPrefix("nameserver") {
                    if let ip = lineStr.split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
                       isPrivateIP(ip) {
                        dnsServers.append(ip)
                    }
                } else if inResolver1 && !lineStr.hasPrefix(" ") && !lineStr.hasPrefix("\t") {
                    break
                }
            }
        } catch {
            if let gw = gateway, isPrivateIP(gw) {
                dnsServers.append(gw)
            } else {
                return names
            }
        }
        
        guard !dnsServers.isEmpty else { return names }
        
        let maxLookups = 30
        for (index, ip) in ips.enumerated() {
            guard index < maxLookups else { break }
            
            do {
                let result = try runCommand("dig", ["-x", ip, "+short"], timeout: 3.0)
                let hostname = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ".", with: "")
                
                if !hostname.isEmpty && hostname != ip {
                    names[ip] = hostname
                }
            } catch {
                // Skip failed lookups silently
            }
        }
        
        return names
    }
    
    // MARK: - Full Device Discovery
    
    static func discoverDevices() async throws -> [NetworkDevice] {
        let route = try await SystemInfo.defaultRoute()
        
        var devices = try await Self.readArp()
        
        // Filter to same /24 subnet
        devices = devices.filter { device in
            let dp = device.ip.split(separator: ".").compactMap { Int($0) }
            let lp = route.localIP.split(separator: ".").compactMap { Int($0) }
            guard dp.count == 4, lp.count == 4 else { return true }
            return dp[0] == lp[0] && dp[1] == lp[1] && dp[2] == lp[2]
        }
        
        // Add this computer if not already in list
        let hasLocal = devices.contains { $0.ip == route.localIP }
        if !hasLocal {
            devices.append(NetworkDevice(
                ip: route.localIP, hostname: ProcessInfo.processInfo.hostName, isThisComputer: true
            ))
        }
        
        // Add gateway if not already in list
        let hasGateway = devices.contains { $0.ip == route.gateway }
        if !hasGateway {
            devices.append(NetworkDevice(ip: route.gateway, isGateway: true))
        }
        
        // Reverse DNS for non-local devices
        let otherIPs = devices.filter { !$0.isThisComputer && !$0.isGateway }.map { $0.ip }
        let names = await reverseDNS(for: otherIPs, gateway: route.gateway)
        
        for i in devices.indices {
            if let name = names[devices[i].ip] {
                devices[i].hostname = name
            }
        }
        
        // Sort: gateway first, then this computer, then by IP
        devices.sort { a, b in
            if a.isGateway != b.isGateway { return a.isGateway }
            if a.isThisComputer != b.isThisComputer { return a.isThisComputer }
            return a.ip < b.ip
        }
        
        return devices
    }
}
