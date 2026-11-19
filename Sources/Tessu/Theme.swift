import SwiftUI
import TessuCore

/// Colour and shape tokens. Native system colours for status so Dark Mode, Increase Contrast and
/// colour-blind settings behave; one violet accent carries the Tessu identity.
enum Theme {
    static let accent = Color(red: 0.486, green: 0.424, blue: 1.0)      // #7C6CFF
    static let lavender = Color(red: 0.718, green: 0.663, blue: 1.0)    // #B7A9FF
    static let corner: CGFloat = 14

    static func color(_ status: CheckStatus) -> Color {
        switch status {
        case .risk: return Color(red: 1.0, green: 0.31, blue: 0.27)
        case .warn: return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .ok: return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .unknown: return Color.secondary
        }
    }

    /// One word per status everywhere: radar label, legend, summary and row tag. Severity is secondary.
    static func word(_ status: CheckStatus) -> String {
        switch status {
        case .risk: return "Open"
        case .warn: return "Review"
        case .ok: return "Sealed"
        case .unknown: return "Unknown"
        }
    }

    static func symbol(_ status: CheckStatus) -> String {
        switch status {
        case .risk: return "exclamationmark.octagon.fill"
        case .warn: return "eye.fill"
        case .ok: return "checkmark.shield.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    static func providerColor(_ id: ProviderID) -> Color {
        switch id.base {
        case .claude: return Color(red: 0.91, green: 0.63, blue: 0.50)   // clay
        case .openai: return Color(red: 0.33, green: 0.78, blue: 0.58)   // mint
        case .openrouter: return Color(red: 0.78, green: 0.55, blue: 0.95) // violet
        case .local: return Color(red: 0.55, green: 0.80, blue: 0.80)      // teal
        default: return Color(red: 0.36, green: 0.69, blue: 0.95)        // sky
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

struct StatusPill: View {
    var status: CheckStatus
    var severity: Severity?

    var body: some View {
        HStack(spacing: 4) {
            Text(Theme.word(status)).fontWeight(.semibold)
            if let s = severity, status == .risk || status == .warn {
                Text(s.rawValue).opacity(0.75)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(Theme.color(status))
        .background(Theme.color(status).opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct SectionTitle: View {
    var title: String
    var detail: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            if let d = detail { Text(d).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct EmptyNote: View {
    var text: String
    var symbol = "info.circle"
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A page wrapper: title, scrollable content, consistent margins.
struct Page<Content: View, Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.largeTitle.weight(.semibold))
                        if let s = subtitle { Text(s).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    trailing
                }
                content
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}
