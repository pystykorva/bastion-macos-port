import Foundation

extension Scan {
    /// A plain-HTTP admin page means the router password crosses the local network unencrypted.
    static func webAdmin(_ ctx: ScanContext) -> CheckResult {
        guard let gw = ctx.gw, let ports = ctx.ports else {
            return result("web-admin-http", .unknown, .medium, "The router address is unknown, so the admin page could not be tested.")
        }
        if ports.routerSilent { return result("web-admin-http", .unknown, .medium, silentEvidence(gw)) }
        let http = ports.results[80] == .open
        let https = ports.results[443] == .open
        if http && !https {
            return result("web-admin-http", .warn, .medium,
                          "The router admin page answers on http://\(gw)/ (TCP 80) and not on HTTPS (TCP 443), so the admin password crosses your network unencrypted.",
                          fix: Fix(label: "Use the admin page only over a wired or trusted connection", steps: [
                            loginStep(gw),
                            "If the router has an option for HTTPS management, turn it on and use https:// from now on.",
                            "Otherwise change router settings only from a computer you trust, and never with guests on your Wi-Fi.",
                          ], open: .routerAdmin),
                          title: "Router admin page is not encrypted")
        }
        if https {
            return result("web-admin-http", .ok, .medium, "The router admin page answers over HTTPS (TCP \(gw):443).", title: "Router admin page supports HTTPS")
        }
        return result("web-admin-http", .ok, .medium, "No admin page answers on TCP \(gw):80 or 443.", title: "No plain-HTTP admin page found")
    }
}
