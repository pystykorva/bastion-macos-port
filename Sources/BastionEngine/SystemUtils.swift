// SystemUtils.swift - macOS system command execution utilities

import Foundation

enum SystemError: Error {
    case commandNotFound(String)
    case executionFailed(String, Int32?)
    case timeout(String)
    case invalidOutput(String)
}

struct CommandResult {
    var stdout: String = ""
    var stderr: String = ""
    var exitCode: Int32?
}

// MARK: - Command Execution

func runCommand(_ program: String, _ args: [String] = [], timeout: TimeInterval = 10.0) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [program] + args
    
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    
    try process.run()
    
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    
    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
    
    let startTime = Date()
    while process.isRunning && Date().timeIntervalSince(startTime) < timeout {
        Thread.sleep(forTimeInterval: 0.1)
    }
    
    if process.isRunning {
        process.terminate()
        throw SystemError.timeout(program)
    }
    
    return CommandResult(
        stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
        stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
        exitCode: process.terminationStatus
    )
}

// MARK: - MAC Address Utilities

func normalizeMAC(_ mac: String?) -> String? {
    guard let mac = mac, !mac.isEmpty else { return nil }
    let cleaned = mac.lowercased().replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: "-", with: "")
    guard cleaned.count == 12 else { return nil }
    let parts = cleaned.map { String($0) }
    return [parts[0..2], parts[2..4], parts[4..6], parts[6..8], parts[8..10], parts[10..12]]
        .joined(separator: ":")
}

func isRandomizedMAC(_ mac: String?) -> Bool {
    guard let mac = normalizeMAC(mac) else { return false }
    let parts = mac.split(separator: ":")
    guard parts.count >= 1 else { return false }
    // Bit 1 of first octet = locally administered
    let firstByte = UInt8(parts[0], radix: 16) ?? 0
    return (firstByte & 0x02) != 0
}

// MARK: - OUI / Vendor Lookup

private let ouiTable: [String: String] = {
    var table: [String: String] = [:]
    
    let entries: [(String, String)] = [
        ("000393", "Apple"), ("000502", "Apple"), ("000A27", "Apple"), ("000A95", "Apple"),
        ("0010FA", "Apple"), ("001124", "Apple"), ("001451", "Apple"), ("0016CB", "Apple"),
        ("3C0754", "Apple"), ("406C8F", "Apple"), ("70CD60", "Apple"), ("7C6D62", "Apple"),
        ("ACBC32", "Apple"), ("F01898", "Apple"), ("28CFE9", "Apple"), ("A483E7", "Apple"),
        ("0000F0", "Samsung"), ("000278", "Samsung"), ("001247", "Samsung"),
        ("3C5AB4", "Google"), ("546009", "Google"), ("94EB2C", "Google"),
        ("18B430", "Google Nest"), ("641666", "Google Nest"),
        ("00FC8B", "Amazon"), ("0C47C9", "Amazon"), ("18742E", "Amazon"),
        ("00014A", "Sony"), ("0013A9", "Sony"),
        ("001C62", "LG"),
        ("009EC8", "Xiaomi"), ("0C1DAF", "Xiaomi"),
        ("0002B3", "Intel"), ("000347", "Intel"),
        ("0050F2", "Microsoft"), ("281878", "Microsoft"),
        ("005056", "VMware"), ("000C29", "VMware"),
        ("080027", "VirtualBox"),
        ("001D0F", "TP-Link"), ("002719", "TP-Link"),
        ("00095B", "Netgear"), ("000FB5", "Netgear"),
        ("000C6E", "ASUS"), ("00112F", "ASUS"),
        ("00E0FC", "Huawei"),
        ("0015EB", "ZTE"),
        ("00040E", "AVM (FRITZ!Box)"), ("001C4A", "AVM (FRITZ!Box)"),
        ("00156D", "Ubiquiti"), ("002722", "Ubiquiti"),
        ("000C42", "MikroTik"),
        ("50FF20", "Keenetic"),
        ("001349", "Zyxel"),
        ("00055D", "D-Link"),
        ("00045A", "Linksys"),
        ("B827EB", "Raspberry Pi"), ("DCA632", "Raspberry Pi"),
        ("18FE34", "Espressif"), ("5CCF7F", "Espressif"),
        ("0009BF", "Nintendo"),
        ("B0A737", "Roku"),
        ("000E58", "Sonos"),
        ("001788", "Philips Hue"),
        ("001E0B", "HP"),
        ("001422", "Dell"),
        ("28D244", "Lenovo"),
        ("94652D", "OnePlus"),
        ("001132", "Synology"),
        ("00089B", "QNAP"),
        ("4419B6", "Hikvision"),
        ("3CEF8C", "Dahua"),
        ("00000C", "Cisco"),
    ]
    
    for (prefix, vendor) in entries {
        table[prefix.uppercased()] = vendor
    }
    
    return table
}()

func lookupVendor(mac: String?) -> String? {
    guard let mac = normalizeMAC(mac) else { return nil }
    let first6 = mac.replacingOccurrences(of: ":", with: "").prefix(6).uppercased()
    return ouiTable[String(first6)]
}

// MARK: - IP Utilities

func isPrivateIP(_ ip: String) -> Bool {
    let parts = ip.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4 else { return false }
    
    // 10.x.x.x
    if parts[0] == 10 { return true }
    // 172.16-31.x.x
    if parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31 { return true }
    // 192.168.x.x
    if parts[0] == 192 && parts[1] == 168 { return true }
    // 127.x.x.x (loopback)
    if parts[0] == 127 { return true }
    
    return false
}
