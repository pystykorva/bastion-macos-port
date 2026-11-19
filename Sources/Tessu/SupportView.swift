import SwiftUI
import TessuCore

/// Feedback. Where it goes is decided at build time by the developer (see FeedbackConfig and
/// scripts/package.sh), never by the source tree. Tessu itself sends nothing: it opens the user's mail
/// app or browser with the text filled in, so the user reads and approves every word first.
struct SupportView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case idea, bug, love
        var id: String { rawValue }
        var label: String { self == .idea ? "Idea" : self == .bug ? "Bug report" : "Kind words" }
        var placeholder: String {
            switch self {
            case .idea: return "What would make Tessu more useful on your network?"
            case .bug: return "What happened, and what did you expect instead?"
            case .love: return "What do you like about Tessu?"
            }
        }
    }

    static let maxMessage = 2000
    static let ratingWords = ["Not great", "Could be better", "It is okay", "Pretty good", "Love it"]

    @EnvironmentObject var state: AppState
    @State var kind: Kind = .idea
    @State var message = ""
    @State var rating = 0
    @State var includeSystem = false
    let config = FeedbackConfig.current

    var body: some View {
        Page(title: "Support", subtitle: "Tell the developer what works and what does not.") {
            EmptyView()
        } content: {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Kind", selection: $kind) { ForEach(Kind.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                    editor
                    HStack {
                        rater
                        Spacer()
                        Text("\(message.count)/\(Self.maxMessage)").font(.caption.monospacedDigit())
                            .foregroundStyle(message.count > Self.maxMessage ? Theme.color(.risk) : .secondary)
                    }
                    Toggle("Include app version, macOS version and Mac type", isOn: $includeSystem)
                    if includeSystem { Text(Self.systemLines()).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    buttons
                    Label(config.destination, systemImage: config.isConfigured ? "paperplane" : "exclamationmark.circle")
                        .font(.caption).foregroundStyle(config.isConfigured ? Color.secondary : Theme.color(.warn))
                    Text("Your mail app or browser opens with the text filled in. Nothing is sent until you press Send or Submit there. Your network, Wi-Fi name and devices are never included.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        HStack {
            if config.email != nil {
                Button { sendMail() } label: { Label("Write an email", systemImage: "envelope") }
                    .buttonStyle(.borderedProminent).disabled(!valid)
            }
            if config.issuesURL != nil {
                let issue = Button { openIssue() } label: { Label("Open a prefilled issue", systemImage: "arrow.up.forward.app") }
                if config.email == nil { issue.buttonStyle(.borderedProminent).disabled(!valid) }
                else { issue.buttonStyle(.bordered).disabled(!valid) }
            }
            Button { copy() } label: { Label("Copy text", systemImage: "doc.on.doc") }.disabled(message.isEmpty)
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $message).font(.body).frame(minHeight: 130)
                .scrollContentBackground(.hidden).padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
            if message.isEmpty { Text(kind.placeholder).foregroundStyle(.tertiary).padding(14).allowsHitTesting(false) }
        }
    }

    private var rater: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Button { rating = rating == i ? 0 : i } label: {
                    Image(systemName: i <= rating ? "star.fill" : "star").foregroundStyle(i <= rating ? Theme.color(.warn) : .secondary)
                }
                .buttonStyle(.plain).accessibilityLabel("\(i) of 5 stars")
            }
            if rating > 0 { Text(Self.ratingWords[rating - 1]).font(.caption).foregroundStyle(.secondary).padding(.leading, 6) }
        }
    }
}
