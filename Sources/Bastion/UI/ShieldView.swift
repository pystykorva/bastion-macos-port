// ShieldView.swift - Security scan view

import SwiftUI

struct ShieldView: View {
    @State private var scanResult: RouterScanner.ScanResult?
    @State private var isScanning = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Score header
                if let scan = scanResult {
                    ScoreGaugeView(score: scan.score)
                        .padding(.top, 10)
                } else {
                    ScoreGaugeView(loading: true)
                        .padding(.top, 10)
                }
                
                // Scan button
                Button(action: runScan) {
                    HStack {
                        if isScanning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Image(systemName: isScanning ? "spinner" : "shield.fill")
                        Text(isScanning ? "Scanning..." : "Run Full Security Scan")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isScanning ? Color.gray : Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
                .disabled(isScanning)
                
                // Open ports
                if let scan = scanResult, !scan.openPorts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Open Ports on Router")
                            .font(.headline)
                        
                        ForEach(scan.openPorts, id: \.port) { port in
                            HStack {
                                Text("\(port.port)")
                                    .font(.monospacedDigit())
                                    .fontWeight(.bold)
                                    .frame(width: 50, alignment: .trailing)
                                
                                Text(port.service)
                                    .font(.subheadline)
                                
                                let risk = riskyPort(port.port)
                                if risk == .high {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                } else if risk == .critical {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                
                // Check list
                if let scan = scanResult {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Security Checks")
                            .font(.headline)
                        
                        ForEach(scan.checks, id: \.id) { check in
                            CheckRow(check: check)
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
            await loadScan()
        }
    }
    
    private func runScan() {
        isScanning = true
        Task {
            scanResult = await BastionEngine.runScan()
            isScanning = false
        }
    }
    
    private func loadScan() async {
        scanResult = await BastionEngine.runScan()
    }
    
    private func riskyPort(_ port: Int) -> String {
        switch port {
        case 21, 23, 7547: return "critical"
        case 22, 80, 8080: return "high"
        default: return "none"
        }
    }
}

struct CheckRow: View {
    let check: ScanCheck
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon(for: check.status))
                .foregroundStyle(statusColor(for: check.status))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(check.title)
                        .font(.subheadline.weight(.medium))
                    
                    if check.severity != .info {
                        Text(check.severity.rawValue.capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor(for: check.status).opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                
                Text(check.evidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func statusIcon(_ status: ScanCheck.Status) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .risk: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    private func statusColor(_ status: ScanCheck.Status) -> Color {
        switch status {
        case .ok: return .green
        case .warn: return .orange
        case .risk: return .red
        case .unknown: return .gray
        }
    }
}

#Preview {
    ShieldView()
}
