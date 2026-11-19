import Foundation

// Checks that look at the router's TCP ports. The wording is kept from the original project so
// findings read the same.

extension Scan {
    static func tr069(_ ctx: ScanContext) -> CheckResult {
        guard let gw = ctx.gw, let ports = ctx.ports else {
            return result("tr069", .unknown, .critical, "The router address is unknown, so the provider management port could not be tested.")
        }
        if ports.routerSilent { return result("tr069", .unknown, .critical, silentEvidence(gw)) }
        let open = [7547, 4567, 30005].filter { ports.results[$0] == .open }
        guard let first = open.first else {
            return result("tr069", .ok, .critical,
                          "TCP \(gw):7547, 4567 and 30005 do not answer on your local network. This test runs from inside your network, so it cannot prove what the router allows from the internet side.",
                          title: "Provider management port is closed")
        }
        let also = open.count > 1 ? " Also open: \(open.dropFirst().map(String.init).joined(separator: ", "))." : ""
        return result("tr069", .risk, .critical,
                      "TCP \(gw):\(first) answers on your local network. This is the TR-069/CWMP remote-management port your provider uses to change router settings and firmware. " +
                      "Tessu cannot prove from inside your network whether it is also reachable from the internet; providers normally keep it reachable for themselves.\(also)",
                      fix: Fix(label: "Turn off provider remote management", steps: [
                        loginStep(gw),
                        "Look for a section called TR-069, CWMP, Remote management, ACS or \"Provider settings\" (often under Advanced, System or Management).",
                        "Disable it and save, if the router allows it.",
                        "If your provider locks this setting, put your own router behind the provider box (provider box in bridge mode, or your router plugged into it) so the provider can only manage its own device.",
                        "Run the scan again to confirm the port no longer answers.",
                      ], open: .routerAdmin),
                      title: "Your provider can reach your router")
    }

    static func portCheck(_ ctx: ScanContext, id: String, port: Int, openStatus: CheckStatus, severity: Severity,
                          openTitle: String, okTitle: String, openEvidence: (String) -> String, fix: Fix) -> CheckResult {
        guard let gw = ctx.gw, let ports = ctx.ports else {
            return result(id, .unknown, severity, "The router address is unknown, so this port could not be tested.")
        }
        if ports.routerSilent { return result(id, .unknown, severity, silentEvidence(gw)) }
        if ports.results[port] == .open { return result(id, openStatus, severity, openEvidence(gw), fix: fix, title: openTitle) }
        return result(id, .ok, severity, "TCP \(gw):\(port) does not answer.", title: okTitle)
    }

    static func telnet(_ ctx: ScanContext) -> CheckResult {
        portCheck(ctx, id: "telnet", port: 23, openStatus: .risk, severity: .high,
                  openTitle: "Telnet is open on your router", okTitle: "Telnet is closed",
                  openEvidence: { "TCP \($0):23 answers. Telnet sends the router password unencrypted and is a favourite target of router botnets such as Mirai." },
                  fix: Fix(label: "Turn off Telnet", steps: [
                    loginStep(ctx.gw), "Find Telnet (often under System, Management or Remote access).",
                    "Disable it and save. If there is no switch, ask your provider or update the firmware.",
                  ], open: .routerAdmin))
    }

    static func ssh(_ ctx: ScanContext) -> CheckResult {
        portCheck(ctx, id: "ssh", port: 22, openStatus: .warn, severity: .low,
                  openTitle: "SSH is open on your router", okTitle: "SSH is closed",
                  openEvidence: { "TCP \($0):22 answers. SSH is encrypted, but it is one more login that can be guessed if the password is weak." },
                  fix: Fix(label: "Turn off SSH if you do not use it", steps: [
                    loginStep(ctx.gw), "Find SSH or Remote access in the management settings.",
                    "Disable it, or make sure it uses a strong unique password and is not reachable from the internet.",
                  ], open: .routerAdmin))
    }
}
