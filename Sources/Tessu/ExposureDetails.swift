import SwiftUI
import TessuCore

/// What the router actually answered: ports and the openings devices asked it to make (UPnP).
struct ExposureDetails: View {
    var report: ScanReport

    private static let risky: [Int: CheckStatus] = [21: .risk, 23: .risk, 7547: .risk, 22: .warn, 80: .warn, 8080: .warn, 1900: .warn, 5000: .warn]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Router ports that answered", detail: report.openPorts.isEmpty ? nil : "\(report.openPorts.count)")
                    if report.openPorts.isEmpty {
                        EmptyNote(text: "No probed port answered from this computer.", symbol: "checkmark.circle")
                    } else {
                        ForEach(report.openPorts, id: \.port) { p in
                            HStack {
                                let s = Self.risky[p.port] ?? .ok
                                Circle().fill(Theme.color(s == .ok ? .unknown : s)).frame(width: 8, height: 8)
                                Text(String(p.port)).font(.callout.monospacedDigit().weight(.semibold)).frame(width: 56, alignment: .leading)
                                Text(p.service).font(.callout).foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Opened by devices (UPnP)", detail: report.upnpMappings.isEmpty ? nil : "\(report.upnpMappings.count)")
                    if report.upnpMappings.isEmpty {
                        EmptyNote(text: upnpEmpty, symbol: "checkmark.circle")
                    } else {
                        ForEach(Array(report.upnpMappings.enumerated()), id: \.offset) { _, m in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(m.proto) \(m.externalPort) → \(m.internalClient):\(m.internalPort.map(String.init) ?? "?")").font(.callout.monospacedDigit())
                                if !m.description.isEmpty { Text(m.description).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var upnpEmpty: String {
        guard let c = report.checks.first(where: { $0.id == "upnp" }) else { return "The router reported no UPnP port forwards." }
        switch c.status {
        case .ok: return "UPnP is off or the router reported no automatic port forwards."
        case .unknown: return "The UPnP check could not run."
        default: return "The router accepts UPnP requests but listed no open ports."
        }
    }
}
