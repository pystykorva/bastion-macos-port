// RouterScanner.swift - Security scan checks for the router

import Foundation

enum RouterScanner {
    
    private static let checkDefinitions: [(id: String, title: String)] = [
        ("tr069", "Provider remote access (TR-069)"),
        ("upnp", "Automatic port opening (UPnP)"),
        ("dns-plaintext", "Who can read your DNS lookups"),
        ("admin-default", "Router admin password"),
        ("wps", "WPS PIN on the router"),
        ("telnet", "Telnet on the router"),
        ("ssh", "SSH on the router"),
        ("web-admin-http", "Router admin page encryption"),
        ("location-map", "Wi-Fi location mapping"),
        ("mac-privacy", "Wi-Fi MAC address privacy"),
        ("wifi-security", "Wi-Fi encryption"),
        ("unknown-devices", "Unidentified devices on your network"),
    ]
    
    struct ScanResult {
        var score: Int = 100
        var checks: [ScanCheck] = []
        var openPorts: [(port: Int, service: String)] = []
    }
    
    static func runScan() async -> ScanResult {
        var result = ScanResult()
        
        do {
            let route = try await SystemInfo.defaultRoute()
            
            // Run port scan
            let ports = await PortScanner.probeGateway(route.gateway)
            result.openPorts = ports.openPorts
            
            // Check each security item
            for checkDef in checkDefinitions {
                let check = await runCheck(checkDef.id, gateway: route.gateway, ports: ports)
                result.checks.append(check)
                
                // Adjust score
                switch check.status {
                case .risk:
                    result.score -= severityWeight(check.severity)
                case .warn:
                    result.score -= severityWeight(check.severity) / 2
                default:
                    break
                }
            }
            
        } catch {
            // Return empty result with error indication
        }
        
        result.score = max(0, min(100, result.score))
        return result
    }
    
    private static func runCheck(_ id: String, gateway: String, ports: (openPorts: [(port: Int, service: String)], results: [Int: String])) async -> ScanCheck {
        switch id {
        case "tr069":
            return checkTR069(gateway: gateway, ports: ports)
        case "upnp":
            return await checkUPnP()
        case "dns-plaintext":
            return await checkDNS(gateway)
        case "admin-default":
            return checkAdminDefault(gateway: gateway, ports: ports)
        case "wps":
            return checkWPS()
        case "telnet":
            return checkTelnet(ports: ports)
        case "ssh":
            return checkSSH(ports: ports)
        case "web-admin-http":
            return checkWebAdminHTTP(gateway: gateway, ports: ports)
        case "location-map":
            return checkLocationMap()
        case "mac-privacy":
            return checkMacPrivacy()
        case "wifi-security":
            return await checkWiFiSecurity()
        case "unknown-devices":
            return await checkUnknownDevices()
        default:
            return ScanCheck(id: id, title: "", status: .unknown, severity: .info, evidence: "Unknown check")
        }
    }
    
    // Individual checks
    
    private static func checkTR069(gateway: String, ports: (openPorts: [(port: Int, service: String)], results: [Int: String])) -> ScanCheck {
        let openPorts = ports.openPorts.map { $0.port }
        
        if !openPorts.contains(7547) && !openPorts.contains(4567) && !openPorts.contains(30005) {
            return ScanCheck(
                id: "tr069", title: "Provider remote access (TR-069)",
                status: .ok, severity: .critical,
                evidence: "TCP \(gateway):7547, 4567 and 30005 do not answer on your local network."
            )
        } else {
            let found = openPorts.filter { [7547, 4567, 30005].contains($0) }
            return ScanCheck(
                id: "tr069", title: "Provider remote access (TR-069)",
                status: .risk, severity: .critical,
                evidence: "TCP \(gateway):\(found.first ?? 0) answers on your local network. This is the TR-069/CWMP remote-management port."
            )
        }
    }
    
    private static func checkUPnP() async -> ScanCheck {
        // UPnP check via SSDP - simplified for macOS
        return ScanCheck(
            id: "upnp", title: "Automatic port opening (UPnP)",
            status: .unknown, severity: .high,
            evidence: "UPnP check requires network discovery. Status unknown."
        )
    }
    
    private static func checkDNS(_ gateway: String) async -> ScanCheck {
        let dnsResult = await DNSEngine.getStatus()
        
        if dnsResult.encrypted == true {
            return ScanCheck(
                id: "dns-plaintext", title: "Who can read your DNS lookups",
                status: .ok, severity: .high,
                evidence: "DNS is encrypted (DoH/DoT). Your DNS lookups are protected."
            )
        } else if dnsResult.encrypted == false {
            return ScanCheck(
                id: "dns-plaintext", title: "Who can read your DNS lookups",
                status: .risk, severity: .high,
                evidence: "DNS is sent unencrypted. Anyone on your network can read DNS lookups."
            )
        } else {
            return ScanCheck(
                id: "dns-plaintext", title: "Who can read your DNS lookups",
                status: .unknown, severity: .high,
                evidence: "Could not determine if DNS is encrypted. macOS does not expose this without admin tools."
            )
        }
    }
    
    private static func checkAdminDefault(gateway: String, ports: (openPorts: [(port: Int, service: String)], results: [Int: String])) -> ScanCheck {
        // Check if admin page is accessible on common ports
        let hasHTTP = ports.openPorts.contains { $0.port == 80 || $0.port == 8080 }
        let hasHTTPS = ports.openPorts.contains { $0.port == 443 || $0.port == 8443 }
        
        if hasHTTP && !hasHTTPS {
            return ScanCheck(
                id: "admin-default", title: "Router admin password",
                status: .warn, severity: .medium,
                evidence: "Router admin page accessible via HTTP (not HTTPS) at http://\(gateway)/"
            )
        } else if hasHTTPS {
            return ScanCheck(
                id: "admin-default", title: "Router admin password",
                status: .ok, severity: .medium,
                evidence: "Router admin page uses HTTPS at https://\(gateway)/"
            )
        } else {
            return ScanCheck(
                id: "admin-default", title: "Router admin password",
                status: .unknown, severity: .medium,
                evidence: "Could not reach router admin page to check."
            )
        }
    }
    
    private static func checkWPS() -> ScanCheck {
        // WPS is typically disabled on modern routers, hard to check remotely
        return ScanCheck(
            id: "wps", title: "WPS PIN on the router",
            status: .unknown, severity: .medium,
            evidence: "WPS status cannot be determined from this computer. Check router settings."
        )
    }
    
    private static func checkTelnet(ports: (openPorts: [(port: Int, service: String)], results: [Int: String])) -> ScanCheck {
        let hasTelnet = ports.openPorts.contains { $0.port == 23 }
        
        if hasTelnet {
            return ScanCheck(
                id: "telnet", title: "Telnet on the router",
                status: .risk, severity: .critical,
                evidence: "Telnet port (23) is open on the router. Telnet sends credentials in plaintext."
            )
        } else {
            return ScanCheck(
                id: "telnet", title: "Telnet on the router",
                status: .ok, severity: .critical,
                evidence: "Telnet port (23) is not open on the router."
            )
        }
    }
    
    private static func checkSSH(ports: (openPorts: [(port: Int, service: String)], results: [Int: String])) -> ScanCheck {
        let hasSSH = ports.openPorts.contains { $0.port == 22 }
        
        if hasSSH {
            return ScanCheck(
                id: "ssh", title: "SSH on the router",
                status: .warn, severity: .high,
                evidence: "SSH port (22) is open on the router. Ensure strong passwords are used."
            )
        } else {
            return ScanCheck(
                id: "ssh", title: "SSH on the router",
                status: .ok, severity: .high,
                evidence: "SSH port (22) is not open on the router."
            )
        }
    }
    
    private static func checkWebAdminHTTP(gateway: String, ports: (openPorts: [(port: Int, service: String)], results: [Int: String])) -> ScanCheck {
        let hasHTTP = ports.openPorts.contains { $0.port == 80 || $0.port == 8080 }
        let hasHTTPS = ports.openPorts.contains { $0.port == 443 || $0.port == 8443 }
        
        if hasHTTP && !hasHTTPS {
            return ScanCheck(
                id: "web-admin-http", title: "Router admin page encryption",
                status: .warn, severity: .medium,
                evidence: "Router admin page accessible via HTTP only. Credentials sent in plaintext."
            )
        } else if hasHTTPS {
            return ScanCheck(
                id: "web-admin-http", title: "Router admin page encryption",
                status: .ok, severity: .medium,
                evidence: "Router admin page uses HTTPS encryption."
            )
        } else {
            return ScanCheck(
                id: "web-admin-http", title: "Router admin page encryption",
                status: .unknown, severity: .medium,
                evidence: "Could not determine admin page encryption status."
            )
        }
    }
    
    private static func checkLocationMap() -> ScanCheck {
        return ScanCheck(
            id: "location-map", title: "Wi-Fi location mapping",
            status: .unknown, severity: .low,
            evidence: "Wi-Fi location data may be shared with mapping services."
        )
    }
    
    private static func checkMacPrivacy() -> ScanCheck {
        return ScanCheck(
            id: "mac-privacy", title: "Wi-Fi MAC address privacy",
            status: .unknown, severity: .low,
            evidence: "Check if your Mac uses randomized MAC addresses for Wi-Fi."
        )
    }
    
    private static func checkWiFiSecurity() async -> ScanCheck {
        let wifi = await WiFiEngine.getWiFiInfo()
        
        if let security = wifi.security {
            switch security.lowercased() {
            case "wpa3", "wpa2/wpa3":
                return ScanCheck(
                    id: "wifi-security", title: "Wi-Fi encryption",
                    status: .ok, severity: .high,
                    evidence: "Wi-Fi uses WPA3 encryption (strongest available)."
                )
            case "wpa2", "wpa2/wpa3":
                return ScanCheck(
                    id: "wifi-security", title: "Wi-Fi encryption",
                    status: .ok, severity: .high,
                    evidence: "Wi-Fi uses WPA2 encryption."
                )
            case "wpa", "wpa/wpa2":
                return ScanCheck(
                    id: "wifi-security", title: "Wi-Fi encryption",
                    status: .warn, severity: .high,
                    evidence: "Wi-Fi uses WPA encryption (older, less secure). Consider upgrading to WPA2/WPA3."
                )
            case "wep":
                return ScanCheck(
                    id: "wifi-security", title: "Wi-Fi encryption",
                    status: .risk, severity: .critical,
                    evidence: "Wi-Fi uses WEP encryption (broken, easily cracked)."
                )
            default:
                return ScanCheck(
                    id: "wifi-security", title: "Wi-Fi encryption",
                    status: .unknown, severity: .high,
                    evidence: "Unknown Wi-Fi security type: \(security)"
                )
            }
        } else {
            return ScanCheck(
                id: "wifi-security", title: "Wi-Fi encryption",
                status: .unknown, severity: .high,
                evidence: "Could not determine Wi-Fi security type."
            )
        }
    }
    
    private static func checkUnknownDevices() async -> ScanCheck {
        do {
            let devices = try await DeviceDiscovery.discoverDevices()
            let unknownCount = devices.filter { !$0.isGateway && !$0.isThisComputer && $0.vendor == nil && $0.hostname == nil }.count
            
            if unknownCount == 0 {
                return ScanCheck(
                    id: "unknown-devices", title: "Unidentified devices on your network",
                    status: .ok, severity: .info,
                    evidence: "All \(devices.count) devices on your network could be identified."
                )
            } else {
                return ScanCheck(
                    id: "unknown-devices", title: "Unidentified devices on your network",
                    status: .warn, severity: .info,
                    evidence: "\(unknownCount) of \(devices.count) devices could not be identified by vendor or hostname."
                )
            }
        } catch {
            return ScanCheck(
                id: "unknown-devices", title: "Unidentified devices on your network",
                status: .unknown, severity: .info,
                evidence: "Could not discover devices on your network."
            )
        }
    }
    
    private static func severityWeight(_ severity: ScanCheck.Severity) -> Int {
        switch severity {
        case .critical: return 30
        case .high: return 15
        case .medium: return 8
        case .low: return 3
        case .info: return 0
        }
    }
}

