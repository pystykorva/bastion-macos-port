import Foundation

// Checks about this computer and the Wi-Fi it is on.

extension Scan {
    static func dns(_ ctx: ScanContext) -> CheckResult {
        guard let d = ctx.dns, !d.servers.isEmpty else {
            return result("dns-plaintext", .unknown, .high, "The DNS servers for this connection could not be read.")
        }
        let servers = d.servers.joined(separator: ", ")
        let fix = Fix(label: "Switch to encrypted DNS", steps: [
            "Open System Settings > Network, select your connection, then Details > DNS.",
            "Replace the servers with a privacy-focused resolver such as 1.1.1.1 and 1.0.0.1 (Cloudflare) or 9.9.9.9 (Quad9).",
            "For encryption, install that provider's encrypted DNS profile from its website (Cloudflare and Quad9 publish one), or turn on Secure DNS in your browser.",
        ], open: .dnsSettings)
        if d.encrypted == true {
            return result("dns-plaintext", .ok, .high, "DNS goes to \(servers) (\(d.provider ?? "unknown provider")) over an encrypted connection.", title: "Your DNS lookups are encrypted")
        }
        if d.gatewayIsResolver && d.encrypted == false {
            return result("dns-plaintext", .risk, .high,
                          "This computer sends every website name it looks up to \(servers) (your router, which forwards to your provider) without encryption. Your provider can log and alter these lookups.",
                          fix: fix, title: "Your provider sees every site you visit")
        }
        let how = d.encrypted == false ? "without encryption" : "and Tessu cannot confirm whether the lookups are encrypted"
        return result("dns-plaintext", .warn, d.gatewayIsResolver ? .high : .medium,
                      "DNS goes to \(servers) (\(d.provider ?? "unknown provider")) \(how).\(d.note.map { " \($0)" } ?? "")",
                      fix: fix, title: "Your DNS lookups may be readable")
    }

    static func locationMap(_ ctx: ScanContext) -> CheckResult {
        guard let ssid = ctx.wifi?.ssid, !ssid.isEmpty else {
            return result("location-map", .unknown, .low, "The Wi-Fi network name is not available (not connected over Wi-Fi, or the system hides it).")
        }
        if WifiLogic.isNomap(ssid) == true {
            return result("location-map", .ok, .low, "Network \"\(ssid)\" opts out of location mapping.", title: "Your Wi-Fi is not used to map your home")
        }
        return result("location-map", .warn, .low,
                      "Network \"\(ssid)\" does not end in _nomap, so phones passing by report its address to location databases that pin it to your home.",
                      fix: routerFix(ctx, "Opt your Wi-Fi out of location mapping", [
                        "Rename the Wi-Fi network so the name ends in _nomap, for example \"\(ssid.prefix(26))_nomap\". Google and Apple honour this.",
                        "Reconnect your devices to the renamed network (the password stays the same).",
                      ]), title: "Your Wi-Fi helps map your home location")
    }

    static func macPrivacy(_ ctx: ScanContext) -> CheckResult {
        if let a = ctx.wifiAdapter, a.connected, a.blocked {
            return result("mac-privacy", .unknown, .low, LocalNetwork.blockedMessage)
        }
        guard let a = ctx.wifiAdapter, a.connected, let mac = a.mac else {
            return result("mac-privacy", .unknown, .low, "This computer is not connected over Wi-Fi, so its Wi-Fi address could not be checked.")
        }
        if a.randomized == true {
            return result("mac-privacy", .ok, .low, "This computer uses a private (randomized) Wi-Fi address \(mac).", title: "This computer uses a private Wi-Fi address")
        }
        return result("mac-privacy", .warn, .low,
                      "This computer connects with its factory Wi-Fi address \(mac), which lets networks and passers-by recognise it everywhere it goes.",
                      fix: Fix(label: "Turn on a private Wi-Fi address", steps: [
                        "Open System Settings > Wi-Fi and click Details next to your network.",
                        "Set \"Private Wi-Fi address\" to Fixed or Rotating.", "Reconnect to the network.",
                      ], open: .macPrivacy),
                      title: "This computer can be tracked by its Wi-Fi address")
    }
}
