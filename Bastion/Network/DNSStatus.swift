// DNSStatus.swift - DNS server analysis

import Foundation

enum DNSEngine {
    
    static func getStatus() async -> DNSStatus {
        var status = DNSStatus()
        
        do {
            let result = try runCommand("scutil", ["--dns"])
            
            // Parse resolver #1 (default resolver) nameservers
            let lines = result.stdout.split(separator: "\n")
            var inResolver1 = false
            
            for line in lines {
                let lineStr = String(line)
                
                if lineStr.hasPrefix("Resolver #1") || lineStr == "resolver #1" {
                    inResolver1 = true
                } else if inResolver1 && lineStr.hasPrefix("nameserver") {
                    let parts = lineStr.split(separator: ":")
                    if parts.count >= 2 {
                        let ip = String(parts[1]).trimmingCharacters(in: .whitespaces)
                        if !status.servers.contains(ip) {
                            status.servers.append(ip)
                        }
                    }
                } else if inResolver1 && !lineStr.hasPrefix(" ") && !lineStr.hasPrefix("\t") {
                    break // end of resolver #1 block
                }
            }
            
        } catch {
            status.servers = ["DNS lookup failed"]
            return status
        }
        
        // Determine provider
        if status.servers.isEmpty {
            status.servers = ["No DNS servers found"]
            return status
        }
        
        let firstServer = status.servers[0]
        if isPrivateIP(firstServer) {
            // Get gateway to compare
            do {
                let route = try await SystemInfo.defaultRoute()
                status.gatewayIsResolver = (firstServer == route.gateway)
                
                if firstServer == route.gateway {
                    status.provider = "ISP / router"
                } else if firstServer == "8.8.8.8" || firstServer == "8.8.4.4" {
                    status.provider = "Google"
                } else if firstServer == "1.1.1.1" || firstServer == "1.0.0.1" {
                    status.provider = "Cloudflare"
                } else if firstServer == "9.9.9.9" {
                    status.provider = "Quad9"
                } else if firstServer == "94.140.14.14" {
                    status.provider = "AdGuard"
                } else if firstServer == "208.67.222.222" {
                    status.provider = "OpenDNS"
                } else {
                    status.provider = "Other (probably your provider)"
                }
            } catch {
                status.provider = "Local network"
            }
        } else {
            if firstServer == "8.8.8.8" || firstServer == "8.8.4.4" {
                status.provider = "Google"
            } else if firstServer == "1.1.1.1" || firstServer == "1.0.0.1" {
                status.provider = "Cloudflare"
            } else if firstServer == "9.9.9.9" {
                status.provider = "Quad9"
            } else if firstServer == "94.140.14.14" {
                status.provider = "AdGuard"
            } else if firstServer == "208.67.222.222" {
                status.provider = "OpenDNS"
            } else {
                status.provider = firstServer
            }
        }
        
        // macOS doesn't easily show encrypted DNS without admin tools
        status.encrypted = nil
        
        return status
    }
}

