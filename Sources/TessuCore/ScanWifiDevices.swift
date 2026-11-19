import Foundation

extension Scan {
    static func wifiSecurity(_ ctx: ScanContext) -> CheckResult {
        guard let sec = ctx.wifi?.security, !sec.isEmpty else {
            return result("wifi-security", .unknown, .high, "The Wi-Fi encryption type is not available (not connected over Wi-Fi, or the system hides it).")
        }
        let s = sec.uppercased()
        func fix(_ label: String, _ extra: [String]) -> Fix {
            routerFix(ctx, label, ["Open the Wireless security settings."] + extra + ["Save, then reconnect your devices."])
        }
        if Rx.test("WPA3|SAE|OWE", s) {
            return result("wifi-security", .ok, .info, "Your Wi-Fi uses \(sec).", title: "Your Wi-Fi uses the newest encryption")
        }
        if s.contains("WPA2") && !s.contains("TKIP") {
            return result("wifi-security", .ok, .info, "Your Wi-Fi uses \(sec). That is safe with a long password; WPA3 is better if all your devices support it.",
                          fix: fix("Upgrade to WPA3 if available", ["Choose WPA2/WPA3 mixed or WPA3-Personal."]), title: "Your Wi-Fi encryption is solid")
        }
        if Rx.test("OPEN|NONE|WEP", s) {
            return result("wifi-security", .risk, .critical, "Your Wi-Fi uses \(sec): anyone nearby can join or read the traffic.",
                          fix: fix("Turn on WPA2 or WPA3", ["Choose WPA2-Personal (AES) or WPA3-Personal and set a long password."]), title: "Your Wi-Fi is effectively open")
        }
        if Rx.test("TKIP|WPA", s) {
            return result("wifi-security", .risk, .high, "Your Wi-Fi uses \(sec), an outdated mode that can be broken.",
                          fix: fix("Switch to WPA2 (AES) or WPA3", ["Choose WPA2-Personal with AES/CCMP only, or WPA3-Personal."]), title: "Your Wi-Fi uses outdated encryption")
        }
        return result("wifi-security", .unknown, .high, "Tessu does not recognise the Wi-Fi security type \"\(sec)\".")
    }

    static func unknownDevices(_ ctx: ScanContext) -> CheckResult {
        guard let list = ctx.devices else {
            return result("unknown-devices", .unknown, .low, "The device list could not be read.")
        }
        // An empty ARP table caused by a privacy block must never read as "nobody is here".
        if ctx.route.localNetworkBlocked {
            return result("unknown-devices", .unknown, .low, LocalNetwork.blockedMessage)
        }
        let others = list.devices.filter { !$0.isGateway && !$0.isThisComputer }
        let randomized = others.filter(\.randomizedMac)
        let unknownVendor = others.filter { !$0.randomizedMac && $0.vendor == nil }
        let total = randomized.count + unknownVendor.count
        if others.isEmpty {
            if let first = list.errors.first {
                return result("unknown-devices", .unknown, .low, "Device discovery did not complete (\(first)), so Tessu cannot tell who is on your network.")
            }
            return result("unknown-devices", .ok, .info,
                          "No other devices answered on your network during this scan. Devices that are asleep or switched off do not show up.",
                          title: "No other devices answered")
        }
        let n = others.count
        if total == 0 {
            return result("unknown-devices", .ok, .info,
                          "All \(n) other device\(n == 1 ? "" : "s") seen on your network have a recognised maker.", title: "Every device is identified")
        }
        var parts: [String] = []
        if !randomized.isEmpty {
            parts.append("\(randomized.count) \(randomized.count == 1 ? "uses" : "use") a private (randomized) address, which is normal for phones, tablets and laptops")
        }
        if !unknownVendor.isEmpty {
            let ips = unknownVendor.prefix(6).map(\.ip).joined(separator: ", ")
            parts.append("\(unknownVendor.count) \(unknownVendor.count == 1 ? "has" : "have") a maker that is not in Tessu's built-in list (\(ips)\(unknownVendor.count > 6 ? ", ..." : ""))")
        }
        let fix = Fix(label: "Check who is on your network", steps: [
            "Compare the list in the Devices view with the devices you own; a device that is switched off disappears from the list.",
            loginStep(ctx.gw) + " The router's client list often shows device names.",
            "If you find a device you do not recognise, change the Wi-Fi password (and turn off WPS) so it is kicked off.",
        ], open: .routerAdmin)
        return result("unknown-devices", .warn, .info,
                      "\(total) of \(n) other device\(n == 1 ? "" : "s") could not be identified by maker: \(parts.joined(separator: "; ")).",
                      fix: fix, title: "\(total) device\(total == 1 ? "" : "s") could not be identified")
    }
}
