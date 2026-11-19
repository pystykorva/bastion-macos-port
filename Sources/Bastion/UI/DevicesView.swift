// DevicesView.swift - Network devices and connections view

import SwiftUI

struct DevicesView: View {
    @State private var devices: [NetworkDevice] = []
    @State private var connections: [NetworkConnection] = []
    @State private var isLoading = true
    
    enum Section: String, CaseIterable {
        case devices = "Devices"
        case connections = "Connections"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with device count
                HStack {
                    Text("Network Devices")
                        .font(.title2)
                    
                    Spacer()
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("\(devices.count) devices")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Refresh button
                Button(action: refresh) {
                    HStack {
                        Image(systemName: isLoading ? "spinner" : "arrow.clockwise")
                        Text(isLoading ? "Refreshing..." : "Refresh")
                    }
                    .font(.headline)
                }
                .disabled(isLoading)
                
                // Device list
                if !devices.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(devices, id: \.ip) { device in
                            DeviceRow(device: device)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                } else if !isLoading {
                    VStack(spacing: 8) {
                        Image(systemName: "network")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        
                        Text("No devices discovered yet")
                            .font(.headline)
                        
                        Text("Devices will appear once they communicate on the network.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                
                // Connections section (if available)
                if !connections.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Active Connections")
                            .font(.headline)
                        
                        ForEach(connections.prefix(20), id: \.localAddress) { conn in
                            ConnectionRow(connection: conn)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                
                Spacer()
            }
            .padding()
        }
        .task {
            await loadData()
        }
    }
    
    private func refresh() {
        Task {
            await loadData()
        }
    }
    
    private func loadData() async {
        isLoading = true
        
        do {
            devices = try await BastionEngine.getDevices()
        } catch {}
        
        do {
            connections = try await BastionEngine.getConnections()
        } catch {}
        
        isLoading = false
    }
}

struct DeviceRow: View {
    let device: NetworkDevice
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon based on device type
            Image(systemName: deviceIcon(for: device))
                .foregroundStyle(deviceColor(for: device))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(deviceName(for: device))
                        .font(.subheadline.weight(.medium))
                    
                    if device.isGateway {
                        Text("Router")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(3)
                    }
                    
                    if device.isThisComputer {
                        Text("You")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(3)
                    }
                    
                    if device.randomizedMAC {
                        Text("Private")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(device.ip)
                        .font(.caption.monospacedDigit())
                    
                    if let mac = device.mac {
                        Text(mac)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    
                    if let vendor = device.vendor {
                        Text(vendor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
    }
    
    private func deviceIcon(for device: NetworkDevice) -> String {
        if device.isGateway { return "router" }
        if device.isThisComputer { return "laptop" }
        
        // Guess based on vendor
        switch device.vendor?.lowercased() {
        case "apple": return "iphone"
        case "samsung": return "iphone"
        case "google", "google nest": return "phone"
        case "xiaomi": return "phone"
        case "raspberry pi": return "cpu"
        default: return "desktopcomputer"
        }
    }
    
    private func deviceColor(for device: NetworkDevice) -> Color {
        if device.isGateway { return .blue }
        if device.isThisComputer { return .green }
        if device.randomizedMAC { return .orange }
        return .secondary
    }
    
    private func deviceName(for device: NetworkDevice) -> String {
        if device.isGateway { return device.vendor.map { "\($0) Router" } ?? "Router" }
        if device.isThisComputer { return ProcessInfo.processInfo.hostName }
        if let hostname = device.hostname { return hostname }
        if let vendor = device.vendor { return vendor }
        return "Unknown Device"
    }
}

struct ConnectionRow: View {
    let connection: NetworkConnection
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.protocolType == "tcp" ? "network.badge.shield.half.filled" : "wave.3.right")
                .foregroundStyle(connection.state == "ESTABLISHED" ? .green : connection.state == "LISTEN" ? .blue : .secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let process = connection.processName {
                        Text(process)
                            .font(.subheadline.weight(.medium))
                    } else {
                        Text("Unknown")
                            .font(.subheadline)
                    }
                    
                    if let pid = connection.pid {
                        Text("(\(pid))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text("\(connection.protocolType.uppercased()) \(connection.localAddress)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                
                if let remote = connection.remoteIP {
                    Text("-> \(remote)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if let state = connection.state {
                Text(state)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(state == "ESTABLISHED" ? Color.green.opacity(0.15) : state == "LISTEN" ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DevicesView()
}
