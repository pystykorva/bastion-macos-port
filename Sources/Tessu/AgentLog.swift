import SwiftUI
import TessuCore

/// The conversation with the selected agent, newest at the bottom.
struct AgentLog: View {
    @EnvironmentObject var state: AppState
    var provider: ProviderID

    private var messages: [ChatMessage] { state.watch.log.filter { $0.provider == provider } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty && !state.asking.contains(provider) {
                        EmptyNote(text: "No messages yet. Ask a question, or turn on watch mode.", symbol: "bubble.left.and.text.bubble.right")
                            .padding(.top, 20)
                    }
                    ForEach(messages) { m in MessageBubble(message: m).id(m.id) }
                    if state.asking.contains(provider) { TypingBubble(provider: provider).id("typing") }
                }
                .padding(24)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: messages.count) { _, _ in scroll(proxy) }
            .onChange(of: state.asking) { _, _ in scroll(proxy) }
            .onAppear { scroll(proxy, animated: false) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let go: () -> Void = {
            if state.asking.contains(provider) { proxy.scrollTo("typing", anchor: .bottom) }
            else if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
        if animated { withAnimation { go() } } else { go() }
    }
}

struct MessageBubble: View {
    var message: ChatMessage

    private var who: String {
        let time = message.at.formatted(date: .omitted, time: .shortened)
        switch message.role {
        case .me: return "You · \(time)"
        case .sys: return "Tessu\(message.watch ? " · watch" : "") · \(time)"
        case .error: return "\(message.provider.tab) · error\(message.model.map { " · \($0)" } ?? "") · \(time)"
        case .agent: return "\(message.provider.tab)\(message.model.map { " · \($0)" } ?? "")\(message.watch ? " · watch" : "") · \(time)"
        }
    }

    private var tint: Color {
        switch message.role {
        case .me: return Theme.accent
        case .sys: return .secondary
        case .error: return Theme.color(.risk)
        case .agent: return Theme.providerColor(message.provider)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(who).font(.caption).foregroundStyle(.secondary)
            }
            // Model output is Markdown at most: it is rendered as text, never as markup that could do anything.
            Text(rendered).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var background: Color {
        switch message.role {
        case .me: return Theme.accent.opacity(0.12)
        case .error: return Theme.color(.risk).opacity(0.10)
        case .sys: return Color.secondary.opacity(0.08)
        case .agent: return Color.secondary.opacity(0.05)
        }
    }

    private var rendered: AttributedString {
        guard message.role == .agent else { return AttributedString(message.text) }
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.text, options: opts)) ?? AttributedString(message.text)
    }
}

struct TypingBubble: View {
    var provider: ProviderID
    @State private var since = Date()
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.providerColor(provider)).frame(width: 8, height: 8)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let s = Int(ctx.date.timeIntervalSince(since))
                Text("\(provider.tab) is answering · \(s / 60):\(String(format: "%02d", s % 60))").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView().controlSize(.small)
            if provider == .local { Text("Local models can take minutes, especially reasoning models.").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }
}

struct WatchControls: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Watch mode").font(.callout.weight(.medium))
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Watch mode", isOn: Binding(get: { state.watch.on }, set: { state.watch.set($0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
        }
    }

    private var status: String {
        let w = state.watch
        if !w.on { return "Off" }
        if w.running { return "Checking now with \(prefs.provider.tab)" }
        if let next = w.nextAt {
            let left = max(0, Int(next.timeIntervalSinceNow))
            return "Next check in \(left / 60):\(String(format: "%02d", left % 60))"
        }
        return "On"
    }
}
