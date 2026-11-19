import SwiftUI
import TessuCore

/// Credits and licence. MIT requires the original copyright notice and permission text to travel with every
/// copy, binaries included, so the full text of both licences is shipped inside the app and shown here.
struct CreditsView: View {
    static let originalURL = URL(string: "https://github.com/0xCodez/bastion")!

    @State private var showOriginal = false
    @State private var showThis = false

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    var body: some View {
        Page(title: "Credits & licence", subtitle: "Tessu \(version)") {
            EmptyView()
        } content: {
            originalCard
            thisCard
            partsCard
            thanksCard
        }
    }

    private var originalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Based on Bastion", detail: "MIT licence")
                Text("This is a native macOS port of Bastion, created by the Bastion contributors. The scan checks, their wording, the scoring, the Wi-Fi channel advice, the privacy filter for AI questions and the router-vendor table come from their work.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Text("Copyright © 2026 Bastion contributors").font(.callout.weight(.medium))
                HStack {
                    Link(destination: Self.originalURL) { Label("github.com/0xCodez/bastion", systemImage: "arrow.up.forward.square") }
                    Button(showOriginal ? "Hide licence" : "Read licence") { withAnimation { showOriginal.toggle() } }
                }
                if showOriginal { LicenseText(resource: "Bastion-original-LICENSE") }
            }
        }
    }

    private var thisCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Tessu", detail: "MIT licence")
                Text("The native SwiftUI app, the Swift engine, the 2D exposure radar, the local-server and OpenRouter providers, the Keychain storage and the packaging are new work released under the same MIT licence. The original notice above stays with it.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Button(showThis ? "Hide licence" : "Read licence") { withAnimation { showThis.toggle() } }
                if showThis { LicenseText(resource: "Tessu-LICENSE") }
            }
        }
    }

    private var partsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "Built with", detail: nil)
                ForEach(Self.parts, id: \.0) { name, what in
                    HStack(alignment: .firstTextBaseline) {
                        Text(name).font(.callout.weight(.medium)).frame(width: 150, alignment: .leading)
                        Text(what).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                Text("No third-party code is bundled in this app: it uses only Apple's system frameworks.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private static let parts: [(String, String)] = [
        ("SwiftUI & Swift Charts", "Interface, gauges and the channel chart"),
        ("CoreWLAN", "Wi-Fi link details and the neighbour scan"),
        ("Security (Keychain)", "API key storage"),
        ("speed.cloudflare.com", "Speed test endpoints (a public Cloudflare service)"),
        ("api.ipify.org", "Public IP lookup"),
    ]

    private var thanksCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(title: "Trademarks", detail: nil)
                Text("Claude and Anthropic, ChatGPT and OpenAI, Grok and xAI, OpenRouter, LM Studio, Ollama and Cloudflare are trademarks of their owners. Tessu is not affiliated with, endorsed by or sponsored by any of them, or by any router vendor or internet provider.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Provided as is, without warranty. It gives guidance based on what it can observe from this Mac and cannot guarantee that a network is secure. Only scan networks you own or are allowed to test.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A licence text loaded from the app bundle.
struct LicenseText: View {
    var resource: String

    var body: some View {
        ScrollView {
            Text(Self.load(resource)).font(.caption.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }
        .frame(maxHeight: 280)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
    }

    /// Looks in the app's Resources first (packaged build), then next to the source (swift run / debug).
    static func load(_ name: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: "txt"), let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Legal/\(name).txt")
        return (try? String(contentsOf: dev, encoding: .utf8)) ?? "The licence text is missing from this build. The original is at https://github.com/0xCodez/bastion/blob/main/LICENSE"
    }
}
