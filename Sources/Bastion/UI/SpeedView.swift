// SpeedView.swift - Speed test and Wi-Fi view

import SwiftUI

struct SpeedView: View {
    @State private var wifiInfo: WiFiInfo?
    @State private var wifiSurvey: WiFiSurvey?
    @State private var speedResult: SpeedEngine.SpeedResult?
    @State private var isTesting = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Speed test section
                VStack(spacing: 16) {
                    Text("Internet Speed Test")
                        .font(.title2)
                    
                    if let speed = speedResult {
                        HStack(spacing: 40) {
                            SpeedGaugeView(
                                value: speed.pingMs,
                                max: 200,
                                unit: "ms",
                                label: "Ping"
                            )
                            
                            SpeedGaugeView(
                                value: speed.downloadMbps,
                                max: 500,
                                unit: "Mbps",
                                label: "Download"
                            )
                        }
                    } else if isTesting {
                        ProgressView("Testing...")
                            .scaleEffect(1.5)
                    } else {
                        Text("Run a speed test to see your connection metrics")
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(action: runSpeedTest) {
                        HStack {
                            Image(systemName: "gauge.low")
                            Text(isTesting ? "Testing..." : "Test Speed")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isTesting ? Color.gray : Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isTesting)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // Wi-Fi info section
                if let wifi = wifiInfo {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Wi-Fi Connection")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "Network", value: wifi.ssid ?? "Unknown")
                            InfoRow(label: "BSSID", value: wifi.bssid ?? "—")
                            
                            HStack {
                                Text("Band").frame(width: 60)
                                Text(wifi.band ?? "—")
                            }
                            
                            HStack {
                                Text("Channel").frame(width: 60)
                                Text(wifi.channel.map { String($0) } ?? "—")
                            }
                            
                            HStack {
                                Text("Signal").frame(width: 60)
                                if let rssi = wifi.rssi {
                                    HStack(spacing: 8) {
                                        SignalBarView(rssi: rssi)
                                        Text("\(wifi.signalPercent ?? 0)% (\(rssi) dBm)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("—")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            HStack {
                                Text("Security").frame(width: 60)
                                Text(wifi.security ?? "—")
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                
                // Wi-Fi survey section
                if let survey = wifiSurvey, !survey.networks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nearby Networks")
                            .font(.headline)
                        
                        LazyVStack(spacing: 6) {
                            ForEach(survey.networks.prefix(10), id: \.bssid) { network in
                                HStack {
                                    Text(network.ssid)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Text("\(network.band) GHz")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Text("Ch \(network.channel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    if let signal = network.signalPercent {
                                        SignalBarView(rssi: percentToRSSI(signal))
                                            .frame(width: 40)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
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
    
    private func runSpeedTest() {
        isTesting = true
        Task {
            speedResult = await BastionEngine.runSpeedTest()
            isTesting = false
        }
    }
    
    private func loadData() async {
        wifiInfo = await BastionEngine.getWiFiInfo()
        wifiSurvey = await BastionEngine.getWiFiSurvey()
    }
    
    private func percentToRSSI(_ percent: Int) -> Int {
        // Convert 0-100% back to approximate RSSI
        return -100 + (percent * 70 / 100)
    }
}

struct SpeedGaugeView: View {
    let value: Double?
    let max: Double
    let unit: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                
                if let value = value {
                    Circle()
                        .trim(from: 0, to: min(value / max, 1.0))
                        .stroke(
                            LinearGradient(
                                colors: [value > max * 0.7 ? .green : .blue, value > max * 0.7 ? .mint : .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(135))
                }
                
                VStack {
                    Text(value.map { String(format: "%.0f", $0) } ?? "—")
                        .font(.system(size: 28, weight: .bold))
                    
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)
        }
    }
}

struct SignalBarView: View {
    let rssi: Int
    
    private var bars: Int {
        switch rssi {
        case -30...:-50: return 4
        case -50...:-65: return 3
        case -65...:-75: return 2
        default: return 1
        }
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                Rectangle()
                    .fill(i <= bars ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 4, height: CGFloat(8 + i * 5))
                    .cornerRadius(1)
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label).frame(width: 60)
            Text(value)
        }
    }
}

#Preview {
    SpeedView()
}
