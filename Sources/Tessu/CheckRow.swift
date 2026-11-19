import SwiftUI
import TessuCore

/// One scan finding: status, plain-language title, the evidence Tessu observed, and (when there is
/// something to do) the exact steps. Expands in place.
struct CheckRow: View {
    @EnvironmentObject var state: AppState
    var check: CheckResult
    var expanded: Bool
    var highlighted: Bool
    var toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: Theme.symbol(check.status))
                        .font(.title3).foregroundStyle(Theme.color(check.status)).frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(check.title).font(.body.weight(.medium)).multilineTextAlignment(.leading)
                        Text(check.evidence)
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            .lineLimit(expanded || state.prefs.advancedEvidence ? nil : 2)
                    }
                    Spacer(minLength: 8)
                    StatusPill(status: check.status, severity: check.severity)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, let fix = check.fix { FixSteps(fix: fix).padding(.top, 12).padding(.leading, 38) }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .strokeBorder(highlighted ? Theme.color(check.status).opacity(0.7) : Color.secondary.opacity(0.18), lineWidth: highlighted ? 1.5 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityHint(check.fix == nil ? "" : "Shows how to fix it")
    }
}

struct FixSteps: View {
    @EnvironmentObject var state: AppState
    var fix: Fix

    private static let opens: [FixTarget: String] = [
        .routerAdmin: "Opens your router admin page",
        .dnsSettings: "Opens the DNS settings of this computer",
        .wifiSettings: "Opens the Wi-Fi settings of this computer",
        .macPrivacy: "Opens the private Wi-Fi address settings",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fix.label).font(.subheadline.weight(.semibold))
            ForEach(Array(fix.steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1)").font(.caption.monospacedDigit().weight(.semibold))
                        .frame(width: 18, height: 18).background(Theme.accent.opacity(0.18), in: Circle())
                    Text(step).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let target = fix.open {
                HStack {
                    Button { Task { await state.openFix(target) } } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                    Text(Self.opens[target] ?? "").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 2)
            }
            Text("Tessu never changes a setting itself: you review and apply every change.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}

struct PendingRow: View {
    var title: String
    var progress: ScanProgress?

    var body: some View {
        HStack(spacing: 12) {
            if let p = progress, let status = p.status {
                Image(systemName: Theme.symbol(status)).foregroundStyle(Theme.color(status)).frame(width: 26)
            } else if progress != nil {
                ProgressView().controlSize(.small).frame(width: 26)
            } else {
                Image(systemName: "circle.dotted").foregroundStyle(.tertiary).frame(width: 26)
            }
            Text(progress?.title ?? title).foregroundStyle(progress == nil ? .secondary : .primary)
            Spacer()
        }
        .padding(14)
        .background(.background.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}
