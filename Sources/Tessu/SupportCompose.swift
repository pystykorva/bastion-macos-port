import SwiftUI
import TessuCore

extension SupportView {
    var valid: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && message.count <= Self.maxMessage
    }

    static func systemLines() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        return "App: Tessu \(v)\nOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nArch: \(arch)"
    }

    func composed() -> String {
        var parts: [String] = []
        if rating > 0 { parts.append("Rating: \(rating)/5") }
        if includeSystem { parts.append(Self.systemLines()) }
        let head = parts.isEmpty ? "" : parts.joined(separator: "\n") + "\n\n"
        return head + message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sendMail() {
        guard let m = config.mailto(subject: "Tessu feedback: \(kind.label)", body: composed()) else { return }
        if m.truncated {
            copy(quiet: true)
            state.show("The message was too long for an email link. The full text is on your clipboard: paste it over the shortened part.", .warn)
        }
        NSWorkspace.shared.open(m.url)
    }

    func openIssue() {
        guard let i = config.issue(title: "\(kind.label): ", body: composed()) else { return }
        if i.truncated {
            copy(quiet: true)
            state.show("The text was shortened for the link. The full text is on your clipboard.", .warn)
        }
        NSWorkspace.shared.open(i.url)
    }

    func copy(quiet: Bool = false) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(composed(), forType: .string)
        if !quiet { state.show("Copied.") }
    }
}
