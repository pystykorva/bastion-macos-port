import AppKit
import SwiftUI

/// QA aid, off unless TESSU_SNAPSHOT=<dir> is set: after start-up the app saves a PNG of each screen
/// by drawing its own window, so it needs no Screen Recording permission and shows nothing else on the
/// desktop. TESSU_SNAPSHOT_SCREENS=home,shield limits the list. Never active in normal use.
@MainActor
enum SnapshotMode {
    static var isActive: Bool { directory != nil }

    static var directory: URL? {
        guard let p = ProcessInfo.processInfo.environment["TESSU_SNAPSHOT"], !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p, isDirectory: true)
    }

    static func run(_ state: AppState) async {
        guard let dir = directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let env = ProcessInfo.processInfo.environment
        let wait = Double(env["TESSU_SNAPSHOT_WAIT"] ?? "") ?? 14
        let wanted = (env["TESSU_SNAPSHOT_SCREENS"] ?? Screen.allCases.map(\.rawValue).joined(separator: ",")).split(separator: ",").map(String.init)
        // TESSU_SNAPSHOT_HEIGHT=2600 grows the window first, so long screens are captured whole.
        if let h = Double(env["TESSU_SNAPSHOT_HEIGHT"] ?? ""), let w = NSApp.windows.first {
            w.setFrame(NSRect(x: w.frame.minX, y: 0, width: 1180, height: h), display: true)
        }
        try? await Task.sleep(nanoseconds: UInt64(wait * 1e9)) // first scan and feeds
        for raw in wanted {
            guard let screen = Screen(rawValue: raw) else { continue }
            state.selection = screen
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if env["TESSU_SNAPSHOT_SCROLL"] == "bottom", let root = NSApp.windows.first?.contentView {
                scrollToBottom(root)
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
            save(dir.appendingPathComponent("\(raw).png"))
        }
        print("[snapshot] saved to \(dir.path)")
        NSApp.terminate(nil)
    }

    private static func scrollToBottom(_ v: NSView) {
        if let sv = v as? NSScrollView, let doc = sv.documentView, doc.frame.height > sv.contentView.bounds.height {
            sv.contentView.scroll(to: NSPoint(x: 0, y: doc.frame.height - sv.contentView.bounds.height))
            sv.reflectScrolledClipView(sv.contentView)
        }
        v.subviews.forEach(scrollToBottom)
    }

    private static func save(_ url: URL) {
        guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView?.superview ?? NSApp.windows.first?.contentView else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: url) }
    }
}
