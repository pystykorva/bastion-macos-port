import Foundation

/// Everything a check may look at. Each check waits only for the sources it needs.
struct ScanContext: Sendable {
    var gw: String?
    var route: DefaultRoute
    var ports: PortProbeResult?
    var upnp: UpnpStatus?
    var dns: DnsStatus?
    var wifi: WifiInfo?
    var wifiAdapter: Overview.WifiAdapter?
    var devices: DeviceList?
}

public enum Scan {
    /// Order is part of the contract (ScanProgress.index).
    public static let checks: [(id: String, title: String)] = [
        ("tr069", "Provider remote access (TR-069)"),
        ("upnp", "Automatic port opening (UPnP)"),
        ("dns-plaintext", "Who can read your DNS lookups"),
        ("admin-default", "Router admin password"),
        ("wps", "WPS PIN on the router"),
        ("telnet", "Telnet on the router"),
        ("ssh", "SSH on the router"),
        ("web-admin-http", "Router admin page encryption"),
        ("location-map", "Wi-Fi location mapping"),
        ("mac-privacy", "Wi-Fi MAC address privacy"),
        ("wifi-security", "Wi-Fi encryption"),
        ("unknown-devices", "Unidentified devices on your network"),
    ]

    static func title(_ id: String) -> String { checks.first { $0.id == id }?.title ?? id }

    static func result(_ id: String, _ status: CheckStatus, _ severity: Severity, _ evidence: String,
                       fix: Fix? = nil, title: String? = nil) -> CheckResult {
        CheckResult(id: id, title: title ?? Scan.title(id), status: status, severity: severity, evidence: evidence, fix: fix)
    }

    /// 100 minus the weight of every open (full) or reviewable (half) finding.
    public static func score(_ checks: [CheckResult]) -> Int {
        var score = 100.0
        for c in checks {
            let w = Double(c.severity.weight)
            if c.status == .risk { score -= w } else if c.status == .warn { score -= w / 2 }
        }
        return max(0, min(100, Int(score.rounded())))
    }

    static func loginStep(_ gw: String?) -> String {
        "Open the router admin page\(gw.map { " (http://\($0)/)" } ?? "") and sign in. The address and password are usually on a sticker on the router."
    }

    static func silentEvidence(_ gw: String) -> String {
        "The router (\(gw)) did not answer any connection attempt from this computer, so Tessu cannot tell which of its ports are open. " +
        "A VPN, Wi-Fi client isolation or a firewall that drops all traffic to the router can cause this."
    }

    static func routerFix(_ ctx: ScanContext, _ label: String, _ steps: [String]) -> Fix {
        Fix(label: label, steps: [loginStep(ctx.gw)] + steps, open: .routerAdmin)
    }
}
