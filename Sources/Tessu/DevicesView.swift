import SwiftUI
import TessuCore

struct DevicesView: View {
    @EnvironmentObject var state: AppState
    @State private var filter: DeviceFilter = .all
    @State private var query = ""
    @State private var loading = false

    private var devices: [Device] { state.devices?.devices ?? [] }

    private var visible: [Device] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return filter.apply(devices).filter {
            q.isEmpty || [$0.hostname, $0.ip, $0.vendor, $0.mac].compactMap { $0 }.joined(separator: " ").lowercased().contains(q)
        }
    }

    var body: some View {
        Page(title: "Devices", subtitle: "Who is on your network, and where this computer is talking.") {
            HStack {
                if loading { ProgressView().controlSize(.small) }
                Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent)
            }
        } content: {
            if state.devices?.errors.contains(LocalNetwork.blockedMessage) == true { LocalNetworkBanner(text: LocalNetwork.blockedMessage) }
            numerals
            deviceList
            ConnectionsCard(query: query)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search name, IP, vendor, MAC, program")
    }

    private func reload() async {
        loading = true
        await state.load(.devices)
        await state.load(.connections)
        loading = false
    }

    private var numerals: some View {
        HStack(spacing: 12) {
            Stat(label: "Devices seen", value: state.devices == nil ? nil : devices.count, note: nil)
            Stat(label: "Randomized MAC", value: state.devices == nil ? nil : devices.filter(\.randomizedMac).count, note: "private addresses")
            Stat(label: "Unknown vendor", value: state.devices == nil ? nil : devices.filter { $0.vendor == nil }.count, note: "no maker match")
            Stat(label: "Live connections", value: state.connections?.items.count, note: nil)
        }
    }

    private var deviceList: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: "Local network", detail: nil)
                    Picker("Filter", selection: $filter) { ForEach(DeviceFilter.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                }
                if state.devices == nil {
                    HStack { ProgressView().controlSize(.small); Text("Looking for devices…").foregroundStyle(.secondary) }
                } else if visible.isEmpty {
                    EmptyNote(text: devices.isEmpty ? (state.devices?.errors.first ?? "No devices answered.") : "No devices match this filter.",
                              symbol: "magnifyingglass")
                } else {
                    ForEach(visible) { DeviceRow(device: $0) }
                }
                Text("Tessu reads this computer's neighbour table, so a device appears once it has talked on the network recently. Sleeping devices and devices on a guest network may be missing.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}
