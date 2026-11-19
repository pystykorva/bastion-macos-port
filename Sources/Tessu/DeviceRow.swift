import SwiftUI
import TessuCore

struct Stat: View {
    var label: String
    var value: Int?
    var note: String?
    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value.map(String.init) ?? "–").font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(note ?? " ").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DeviceRow: View {
    var device: Device

    private var symbol: String {
        if device.isGateway { return "wifi.router" }
        if device.isThisComputer { return "laptopcomputer" }
        switch Prompt.deviceKind(device.hostname) {
        case "iphone", "ipad", "android", "galaxy", "pixel", "oneplus", "xiaomi", "redmi": return "iphone"
        case "tv", "smarttv", "bravia", "roku", "chromecast", "firetv", "appletv", "apple-tv": return "tv"
        case "printer", "scanner": return "printer"
        case "camera", "cam", "ipcam", "doorbell", "nvr", "dvr": return "web.camera"
        case "echo", "alexa", "google-home", "nest", "sonos", "speaker", "homepod": return "homepodmini"
        default: return "desktopcomputer"
        }
    }

    private var title: String {
        if device.isGateway { return "Router" }
        if device.isThisComputer { return "This computer" }
        return device.hostname ?? device.vendor ?? "Unnamed device"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title3).frame(width: 28).foregroundStyle(Theme.lavender)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.medium))
                    Text([device.hostname.flatMap { $0 == title ? nil : $0 }, device.vendor].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if device.randomizedMac { Tag(text: "private MAC") }
                if device.vendor == nil && !device.randomizedMac && !device.isThisComputer && !device.mac.isEmpty { Tag(text: "unknown maker", warn: true) }
                VStack(alignment: .trailing, spacing: 1) {
                    Text(device.ip).font(.callout.monospacedDigit()).textSelection(.enabled)
                    Text(device.mac).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(.vertical, 6)
            Divider()
        }
        .accessibilityElement(children: .combine)
    }
}

struct Tag: View {
    var text: String
    var warn = false
    var body: some View {
        Text(text).font(.caption2)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background((warn ? Theme.color(.warn) : Color.secondary).opacity(0.15), in: Capsule())
            .foregroundStyle(warn ? Theme.color(.warn) : Color.secondary)
    }
}
