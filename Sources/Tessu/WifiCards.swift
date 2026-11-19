import SwiftUI
import TessuCore

struct WifiLinkCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "Wi-Fi link", detail: nil)
                if let w = state.wifi {
                    if !w.supported {
                        EmptyNote(text: w.errors.first ?? "Tessu could not read the Wi-Fi adapter, so the link details are unknown.", symbol: "wifi.slash")
                    } else if w.channel == nil {
                        EmptyNote(text: w.errors.first ?? "Not connected to Wi-Fi.", symbol: "wifi.slash")
                    } else {
                        row("Network", w.ssid ?? "Hidden by macOS")
                        row("Band", w.band?.label ?? "–")
                        row("Channel", "\(w.channel.map(String.init) ?? "–")\(w.widthMHz.map { " · \($0) MHz" } ?? "")")
                        row("Signal", signal(w))
                        row("Link speed", w.rxMbps.map { "\(Int($0)) Mbps" } ?? "–")
                        row("Security", w.security ?? "–")
                        if state.prefs.advancedEvidence { row("BSSID", w.bssid ?? "–", mono: true) }
                        if w.ssid == nil, w.errors.contains(Wifi.locationHint) { LocationHint() }
                    }
                } else {
                    HStack { ProgressView().controlSize(.small); Text("Reading the Wi-Fi adapter…").foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func signal(_ w: WifiInfo) -> String {
        guard let r = w.rssi else { return "–" }
        let q = r >= -55 ? "excellent" : r >= -67 ? "good" : r >= -75 ? "fair" : "weak"
        return "\(r) dBm · \(q)"
    }

    private func row(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(v).font(mono ? .callout.monospaced() : .callout).textSelection(.enabled)
            Spacer()
        }.font(.callout)
    }
}

struct LocationHint: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Wifi.locationHint).font(.caption).foregroundStyle(.secondary)
            Button("Open Location settings") { state.openLocationSettings() }.controlSize(.small)
        }.padding(.top, 4)
    }
}

struct ChannelsCard: View {
    @EnvironmentObject var state: AppState
    @State private var band: WifiBand = .ghz5
    @State private var asTable = false

    private var bands: [WifiBand] {
        let present = Set(state.survey?.networks.map(\.band) ?? [])
        return [WifiBand.ghz24, .ghz5, .ghz6].filter { present.contains($0) }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: "Channels around you", detail: state.survey.map { "\($0.networks.count) networks heard" })
                    Button { Task { await state.load(.survey) } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Scan again").buttonStyle(.borderless)
                }
                if let s = state.survey {
                    if !s.supported {
                        EmptyNote(text: s.errors.first ?? "Tessu could not scan for nearby networks.", symbol: "wifi.slash")
                    } else if bands.isEmpty {
                        EmptyNote(text: s.errors.first ?? "macOS did not report any nearby networks.", symbol: "wifi.exclamationmark")
                    } else {
                        if let rec = s.recommendation { Recommendation(rec: rec) }
                        else if s.currentChannel != nil { EmptyNote(text: "Your channel is already among the quietest. No change needed.", symbol: "checkmark.circle") }
                        HStack {
                            Picker("Band", selection: $band) { ForEach(bands, id: \.self) { Text($0.label).tag($0) } }
                                .pickerStyle(.segmented).frame(maxWidth: 260).labelsHidden()
                            Spacer()
                            Picker("View", selection: $asTable) { Image(systemName: "chart.bar").tag(false); Image(systemName: "list.bullet").tag(true) }
                                .pickerStyle(.segmented).frame(width: 80).labelsHidden()
                        }
                        if asTable { CongestionTable(survey: s, band: band) }
                        else { ChannelChart(survey: s, band: band, currentChannel: s.currentChannel) }
                        ForEach(s.errors, id: \.self) { e in
                            if e == Wifi.locationHint { LocationHint() } else { Text(e).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                } else {
                    HStack { ProgressView().controlSize(.small); Text("Scanning for nearby networks…").foregroundStyle(.secondary) }
                }
            }
        }
        .onChange(of: state.survey?.currentBand) { _, new in if let new = new { band = new } }
        .onAppear { if let b = state.survey?.currentBand { band = b } }
    }
}

struct Recommendation: View {
    var rec: ChannelRecommendation
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.swap").foregroundStyle(Theme.lavender).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("Move to channel \(rec.channel) on \(rec.band.label)").font(.headline)
                Text(rec.reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Theme.lavender.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
