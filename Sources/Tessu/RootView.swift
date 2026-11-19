import SwiftUI
import TessuCore

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            ZStack(alignment: .bottom) {
                detail
                if let t = state.toast { ToastView(toast: t).padding(20).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .animation(.snappy, value: state.toast)
        }
        .navigationTitle(state.selection == .home ? "Tessu" : state.selection.title)
    }

    @ViewBuilder private var detail: some View {
        switch state.selection {
        case .home: HomeView()
        case .shield: ShieldView()
        case .speed: SpeedView()
        case .devices: DevicesView()
        case .agents: AgentsView()
        case .settings: SettingsView()
        case .support: SupportView()
        case .credits: CreditsView()
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List(selection: Binding(get: { Optional(state.selection) }, set: { if let s = $0 { state.selection = s } })) {
            ForEach(Screen.allCases) { s in
                Label(s.title, systemImage: s.symbol).tag(s)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { StatusFooter().padding(12) }
    }
}

/// The verdict at a glance, always visible: scan state and score.
private struct StatusFooter: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            if state.scanning {
                ProgressView().controlSize(.small)
                Text("Scanning \(state.scanProgress.count)/\(Scan.checks.count)").font(.caption)
            } else if let r = state.scan, !r.checks.isEmpty {
                let level = Verdict.of(r)
                Image(systemName: level.symbol).foregroundStyle(level.color)
                VStack(alignment: .leading, spacing: 0) {
                    Text(level.headline).font(.caption.weight(.semibold))
                    Text("Score \(r.score)").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                Text("Not scanned yet").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ToastView: View {
    var toast: AppState.Toast
    var body: some View {
        Label(toast.text, systemImage: toast.kind == .info ? "info.circle.fill" : "exclamationmark.triangle.fill")
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .shadow(radius: 8, y: 2)
            .frame(maxWidth: 560)
    }
}
