import SwiftUI
import TessuCore

/// A short result line under a provider (green when it worked, red when it did not).
struct ProviderNote {
    var ok: Bool
    var text: String
}

struct NoteLine: View {
    var note: ProviderNote?
    var body: some View {
        if let n = note { Text(n.text).font(.caption).foregroundStyle(n.ok ? Theme.color(.ok) : Theme.color(.risk)) }
    }
}

/// "Use your subscription": the Claude Code / Codex the user is already signed in to.
struct SubscriptionsCard: View {
    @EnvironmentObject var state: AppState
    @State private var checking = false
    @State private var notes: [ProviderID: ProviderNote] = [:]
    @State private var testing: ProviderID?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(title: "Use your subscription", detail: nil)
                    Button { Task { checking = true; await state.loadProviders(refresh: true); checking = false } } label: {
                        if checking { ProgressView().controlSize(.small) } else { Text("Check again") }
                    }
                }
                Text("Run Claude or ChatGPT through the official app you are already signed in to, so answers use your plan and no API key is needed. Tessu starts it with every tool switched off: it can only reply in text.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(state.providers.filter(\.id.isCLI)) { p in row(p) }
                Text("Plan usage limits apply, and a long snapshot counts toward them.").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder private func row(_ p: ProviderInfo) -> some View {
        let c = p.cli
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(Theme.providerColor(p.id)).frame(width: 10, height: 10)
                Text(p.id.tab).font(.headline)
                Text("via \(c?.product ?? "")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                pill(c)
                Button(testing == p.id ? "Testing…" : "Test") { Task { await test(p.id) } }.disabled(c?.installed != true || testing != nil)
            }
            if c?.installed == true, let v = c?.version {
                Text("\(c?.product ?? "") \(v)\(c?.path.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
            }
            if let n = c?.note { Text(n).font(.caption).foregroundStyle(Theme.color(.warn)) }
            if c?.installed != true { command("Install", c?.installCommand ?? "") }
            else if c?.loggedIn == false { command("Sign in", c?.loginCommand ?? "") }
            NoteLine(note: notes[p.id])
        }
        Divider()
    }

    @ViewBuilder private func pill(_ c: CLIStatus?) -> some View {
        if c?.installed != true { Tag(text: "not installed") }
        else if c?.ready == true { Tag(text: "ready") }
        else if c?.loggedIn == false { Tag(text: "not signed in", warn: true) }
        else { Tag(text: "sign-in not checked") }
    }

    private func command(_ label: String, _ text: String) -> some View {
        HStack {
            Text("\(label):").font(.caption).foregroundStyle(.secondary)
            Text(text).font(.caption.monospaced()).textSelection(.enabled)
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help("Copy")
        }
    }

    private func test(_ id: ProviderID) async {
        testing = id; notes[id] = nil
        let r = await state.agents.test(id)
        notes[id] = r.ok ? ProviderNote(ok: true, text: "Works. Answered with \(r.model).") : ProviderNote(ok: false, text: r.error ?? "The test failed.")
        testing = nil
        await state.loadProviders()
    }
}
