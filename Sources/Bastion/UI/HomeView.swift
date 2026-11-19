// HomeView.swift - Main dashboard view

import SwiftUI

struct HomeView: View {
    @State private var overview: NetworkOverview?
    @State private var scanResult: RouterScanner.ScanResult?
    @State private var wifiInfo: WiFiInfo?
    @State private var speedResult: SpeedEngine.SpeedResult?
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with score
                if let scan = scanResult {
                    ScoreGaugeView(score: scan.score)
                        .padding(.top, 10)
                } else if isLoading {
                    ScoreGaugeView(loading: true)
                        .padding(.top, 10)
                }
                
                // Network overview cards
                if let overview = overview {
                    HStack(spacing: 16) {
                        NetworkInfoCard(title: "Local IP", value: overview.localIP, icon: "network")
                        NetworkInfoCard(title: "Gateway", value: overview.gatewayIP ?? "—", icon: "router")
                        NetworkInfoCard(title: "Public IP", value: overview.publicIP ?? "—", icon: "globe")
                    }
                } else if isLoading {
                    HStack(spacing: 16) {
                        ForEach(0..<3) { _ in
                            NetworkInfoCardLoading()
                        }
                    }
                }
                
                // Quick scan button
                Button(action: runScan) {
                    HStack {
                        Image(systemName: "shield.checkmark")
                        Text("Run Security Scan")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
                
                // Recent scan summary
                if let scan = scanResult {
                    ScanSummaryView(scan: scan)
                }
                
                // Wi-Fi info
                if let wifi = wifiInfo {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wi-Fi Status")
                            .font(.headline)
                        
                        HStack(spacing: 20) {
                            if let ssid = wifi.ssid {
                                Text("Network: \(ssid)")
                                    .font(.subheadline)
                            }
                            if let channel = wifi.channel {
                                Text("Channel: \(channel)")
                                    .font(.subheadline)
                            }
                            if let band = wifi.band {
                                Text("Band: \(band) GHz")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                
                // Speed test result
                if let speed = speedResult {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Speed Test")
                            .font(.headline)
                        
                        HStack(spacing: 24) {
                            SpeedMetric(label: "Ping", value: speed.pingMs.map { String(format: "%.0f ms", $0) }, color: .green)
                            SpeedMetric(label: "Download", value: speed.downloadMbps.map { String(format: "%.0f Mbps", $0) }, color: .blue)
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
    
    private func loadData() async {
        isLoading = true
        
        do {
            overview = try await BastionEngine.getOverview()
        } catch {}
        
        scanResult = await BastionEngine.runScan()
        wifiInfo = await BastionEngine.getWiFiInfo()
        
        isLoading = false
    }
    
    private func runScan() {
        Task {
            scanResult = await BastionEngine.runScan()
        }
    }
}

// MARK: - Subviews

struct ScoreGaugeView: View {
    let score: Int?
    let loading: Bool
    
    init(score: Int = 0, loading: Bool = false) {
        self.score = score
        self.loading = loading
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Network Security Score")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            if loading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if let score = score {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 12)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100.0 * 0.75)
                        .stroke(
                            LinearGradient(
                                colors: score >= 80 ? [.green, .mint] : score >= 50 ? [.orange, .yellow] : [.red, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(135))
                    
                    Text("\(score)")
                        .font(.system(size: 48, weight: .bold))
                }
                .frame(width: 160, height: 160)
                
                let status = score >= 80 ? "Good" : score >= 50 ? "Fair" : "Needs Attention"
                Text(status)
                    .font(.headline)
                    .foregroundStyle(score >= 80 ? .green : score >= 50 ? .orange : .red)
            }
        }
    }
}

struct NetworkInfoCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct NetworkInfoCardLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 24, height: 24)
            
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 60, height: 12)
            
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 80, height: 16)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct ScanSummaryView: View {
    let scan: RouterScanner.ScanResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan Results")
                .font(.headline)
            
            ForEach(scan.checks, id: \.id) { check in
                HStack {
                    Image(systemName: statusIcon(for: check.status))
                        .foregroundStyle(statusColor(for: check.status))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title)
                            .font(.subheadline)
                        
                        if !check.evidence.isEmpty {
                            Text(check.evidence)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
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

struct SpeedMetric: View {
    let label: String
    let value: String?
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value ?? "—")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    HomeView()
}
