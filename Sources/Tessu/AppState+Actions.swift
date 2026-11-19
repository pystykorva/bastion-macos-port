import SwiftUI
import TessuCore

extension AppState {
    // MARK: scanning

    func runScan() async {
        guard !scanning else { return }
        scanning = true
        scanError = nil
        scanProgress = [:]
        let report = await Scan.run { [weak self] p in
            Task { @MainActor in self?.scanProgress[p.id] = p }
        }
        scan = report
        scanning = false
        if report.checks.isEmpty { scanError = report.errors.first ?? "The scan could not run." }
    }

    // MARK: speed test

    func runSpeed() async {
        guard !speedRunning else { return }
        speedRunning = true
        speedProgress = nil
        let token = CancelToken()
        speedToken = token
        let result = await SpeedTest.run(token: token) { [weak self] p in
            Task { @MainActor in if p.phase != .done { self?.speedProgress = p } }
        }
        speedRunning = false
        speedProgress = nil
        speedToken = nil
        if result.measured {
            speed = result
            speedHistory = Array(([result] + speedHistory).prefix(20))
            prefs.saveSpeedHistory(speedHistory)
        } else if let e = result.errors.first {
            show(e, .warn)
        }
    }

    func cancelSpeed() { speedToken?.cancel() }

    // MARK: guided fixes

    /// Opens a settings page or the router admin page. Never changes anything itself.
    func openFix(_ target: FixTarget) async {
        let r = await Fixes.url(for: target)
        guard let url = r.url else { show(r.error ?? "Could not open that page.", .warn); return }
        NSWorkspace.shared.open(url)
    }

    func openLocalNetworkSettings() {
        if let url = URL(string: LocalNetwork.settingsURL) { NSWorkspace.shared.open(url) }
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") { NSWorkspace.shared.open(url) }
    }
}
