// Connections.swift - Active network connections monitoring

import Foundation

enum ConnectionEngine {
    
    static func getConnections() async throws -> [NetworkConnection] {
        let result = try runCommand("lsof", ["-nP", "-iTCP", "-iUDP"])
        
        var connections: [NetworkConnection] = []
        let seen = Set<String>() // dedup key
        
        for line in result.stdout.split(separator: "\n").dropFirst(1) { // skip header
            let lineStr = String(line).trimmingCharacters(in: .whitespaces)
            
            // Format: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            // Google Chrome 512 me 23u IPv4 0x.. 0t0 TCP 192.168.1.5:52341->142.250.74.14:443 (ESTABLISHED)
            let parts = lineStr.split(separator: "\t")
            guard parts.count >= 4 else { continue }
            
            let processName = String(parts[0])
            guard let pid = Int32(String(parts[1])) else { continue }
            
            // Parse the NAME column (last part)
            let namePart = String(parts[parts.count - 1])
            
            // Skip loopback
            if namePart.contains("127.0.0.1") || namePart.contains("[::1]") { continue }
            
            // Parse TCP/UDP connections
            if namePart.hasPrefix("TCP") || namePart.hasPrefix("UDP") {
                let protocolType = namePart.hasPrefix("TCP") ? "tcp" : "udp"
                
                // Extract local and remote addresses
                var localAddr = ""
                var remoteIP: String?
                var remotePort: Int?
                var state: String?
                
                if protocolType == "tcp" {
                    // TCP 192.168.1.5:52341->142.250.74.14:443 (ESTABLISHED)
                    if let arrowRange = namePart.range(of: "->") {
                        localAddr = String(namePart[namePart.startIndex..<arrowRange.lowerBound])
                        let afterArrow = String(namePart[arrowRange.upperBound...])
                        
                        // Remove state in parentheses
                        if let parenStart = afterArrow.firstIndex(of: "(") {
                            remoteIP = String(afterArrow[afterArrow.startIndex..<parenStart]).trimmingCharacters(in: .whitespaces)
                            state = String(afterArrow[parenStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                                .replacingOccurrences(of: "(", with: "")
                                .replacingOccurrences(of: ")", with: "")
                        } else {
                            remoteIP = afterArrow.trimmingCharacters(in: .whitespaces)
                        }
                    } else {
                        // LISTEN state: TCP *:80 (LISTEN) or TCP 192.168.1.5:80 (LISTEN)
                        localAddr = String(namePart[namePart.index(after: namePart.startIndex)...])
                            .trimmingCharacters(in: .whitespaces)
                        if let parenStart = localAddr.firstIndex(of: "(") {
                            state = String(localAddr[parenStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                                .replacingOccurrences(of: "(", with: "")
                                .replacingOccurrences(of: ")", with: "")
                            localAddr = String(localAddr[localAddr.startIndex..<parenStart]).trimmingCharacters(in: .whitespaces)
                        }
                    }
                } else {
                    // UDP 192.168.1.5:5353
                    localAddr = String(namePart[namePart.index(after: namePart.startIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                }
                
                // Parse address:port
                if let lastColon = localAddr.lastIndex(of: ":") {
                    // Handle IPv6 [::1]:port
                    if localAddr.hasPrefix("[") {
                        // IPv6 format
                    } else {
                        let portStr = String(localAddr[lastColon...])
                            .replacingOccurrences(of: ":", with: "")
                        localAddr = String(localAddr[localAddr.startIndex..<lastColon])
                    }
                }
                
                let dedupKey = "\(protocolType)|\(pid)|\(localAddr)|\(remoteIP ?? "*")"
                if seen.contains(dedupKey) { continue }
                seen.insert(dedupKey)
                
                connections.append(NetworkConnection(
                    processName: processName,
                    pid: pid,
                    protocolType: protocolType,
                    localAddress: localAddr,
                    remoteIP: remoteIP,
                    remotePort: nil, // simplified
                    state: state
                ))
            }
        }
        
        return connections
    }
}

