import Foundation

// Checks that can only advise: what Tessu cannot see from a laptop is reported as unknown, never
// as fine. Tessu never tries passwords on the router.

extension Scan {
    static func adminDefault(_ ctx: ScanContext) -> CheckResult {
        let plainHttp = ctx.ports?.results[80] == .open && ctx.ports?.results[443] != .open
        let extra = plainHttp ? " The admin page at http://\(ctx.gw ?? "")/ is plain HTTP, so the password also travels unencrypted on your network." : ""
        return result("admin-default", .unknown, .medium,
                      "Tessu never tries passwords on your router, so it cannot tell whether the factory password is still set.\(extra)",
                      fix: Fix(label: "Change the router admin password", steps: [
                        loginStep(ctx.gw), "Find Administration, System or Management > Password.",
                        "Set a long unique password (a password manager can generate one). Do not reuse the one on the sticker or your Wi-Fi password.",
                        "If the router offers remote/WAN administration, turn it off.",
                      ], open: .routerAdmin),
                      title: "Router admin password not verified")
    }

    static func wps(_ ctx: ScanContext) -> CheckResult {
        result("wps", .unknown, .medium,
               "Whether WPS is on can only be seen in the router settings. The WPS PIN can be brute-forced in hours on many routers.",
               fix: Fix(label: "Turn off WPS", steps: [
                loginStep(ctx.gw), "Find WPS (usually under Wireless or Wi-Fi settings).",
                "Turn WPS off completely, or at least disable the PIN method, and save. Connect new devices with the Wi-Fi password instead.",
               ], open: .routerAdmin),
               title: "WPS status not verified")
    }

    static func upnp(_ ctx: ScanContext) -> CheckResult {
        guard let u = ctx.upnp else { return result("upnp", .unknown, .high, "The UPnP check could not run.") }
        let steps = [
            loginStep(ctx.gw), "Find UPnP (usually under Advanced, NAT forwarding or Network).",
            "Turn it off and save. Games or apps that need open ports can be given manual port-forwarding rules instead.",
        ]
        if !u.found {
            return result("upnp", .ok, .medium,
                          "No UPnP Internet Gateway Device answered on the local network within 2.5 seconds, so apps cannot open router ports automatically.",
                          title: "UPnP port opening is off")
        }
        let who = [u.manufacturer, u.modelName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let name = who.isEmpty ? (u.friendlyName ?? "Your router") : who
        let fix = Fix(label: "Turn off UPnP", steps: steps, open: .routerAdmin)
        if !u.mappings.isEmpty {
            let list = u.mappings.prefix(8).map { m in
                "\(m.proto) \(m.externalPort) -> \(m.internalClient):\(m.internalPort.map(String.init) ?? "?")\(m.description.isEmpty ? "" : " (\(m.description))")"
            }.joined(separator: "; ")
            return result("upnp", .warn, .high,
                          "\(name) accepts UPnP requests and currently has \(plural(u.mappings.count, "port", "ports")) opened to the internet by devices on your network: \(list)\(u.mappings.count > 8 ? "; ..." : "").",
                          fix: fix, title: "Devices have opened ports to the internet")
        }
        let now = u.mappingsReadable
            ? "No ports are open through it right now."
            : "The router would not list its current port openings (\(u.mappingsProblem ?? "unknown reason")), so Tessu cannot tell whether any are open right now."
        return result("upnp", .warn, .medium,
                      "\(name) accepts UPnP requests (\(u.location ?? "local network")). \(now) Any app or infected device on your network can open a port to the internet without asking.",
                      fix: fix, title: "Any device can open ports on your router")
    }
}
