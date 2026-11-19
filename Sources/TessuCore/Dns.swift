import Foundation

public enum Dns {
    static let providers: [String: String] = [
        "1.1.1.1": "Cloudflare", "1.0.0.1": "Cloudflare", "1.1.1.2": "Cloudflare", "1.0.0.2": "Cloudflare",
        "1.1.1.3": "Cloudflare", "1.0.0.3": "Cloudflare",
        "8.8.8.8": "Google", "8.8.4.4": "Google",
        "9.9.9.9": "Quad9", "149.112.112.112": "Quad9", "9.9.9.10": "Quad9", "9.9.9.11": "Quad9",
        "94.140.14.14": "AdGuard", "94.140.15.15": "AdGuard",
        "208.67.222.222": "OpenDNS", "208.67.220.220": "OpenDNS",
        "77.88.8.8": "Yandex", "77.88.8.1": "Yandex",
        "2606:4700:4700::1111": "Cloudflare", "2606:4700:4700::1001": "Cloudflare",
        "2001:4860:4860::8888": "Google", "2001:4860:4860::8844": "Google",
        "2620:fe::fe": "Quad9", "2620:fe::9": "Quad9",
    ]

    static func provider(for servers: [String], gateway: String?) -> String? {
        guard let first = servers.first else { return nil }
        if let known = providers[first] { return known }
        if first == gateway || NetUtil.isPrivateIPv4(first) || Rx.test("^(fe80:|fd|fc)", first, options: .caseInsensitive) {
            return "ISP / router"
        }
        return "Other (probably your provider)"
    }

    /// The first "DNS configuration" section, resolver #1, is the default resolver; per-domain
    /// resolvers (for example .local) are skipped.
    static func parseScutil(_ text: String) -> [String] {
        let main = text.components(separatedBy: "DNS configuration (for scoped queries)").first ?? text
        var servers: [String] = []
        let blocks = Rx.all("(?:^|\\n)resolver #\\d+([\\s\\S]*?)(?=\\nresolver #\\d+|$)", in: main).map { $0[1] }
        for block in blocks {
            if Rx.test("domain\\s*:\\s*\\S+", block, options: .caseInsensitive), !Rx.test("search domain", block, options: .caseInsensitive) { continue }
            for m in Rx.all("nameserver\\[\\d+\\]\\s*:\\s*(\\S+)", in: block) where !servers.contains(m[1]) {
                servers.append(m[1])
            }
            if !servers.isEmpty { break }
        }
        return servers
    }

    public static func status() async -> DnsStatus {
        var out = DnsStatus()
        let route = await SystemInfo.defaultRoute()
        let res = await Exec.run("/usr/sbin/scutil", ["--dns"], timeout: 5)
        if let e = res.error { out.errors.append(e) }
        out.servers = parseScutil(res.stdout)
        // macOS does not show whether an encrypted DNS profile is active without admin tools.
        out.encrypted = nil
        out.provider = provider(for: out.servers, gateway: route.gateway)
        out.gatewayIsResolver = out.servers.contains { $0 == route.gateway || (NetUtil.isIPv4($0) && NetUtil.isPrivateIPv4($0)) }
        out.note = "macOS does not show whether an encrypted DNS profile is active without admin tools, so encryption is reported as unknown."
        if out.servers.isEmpty { out.errors.append("No DNS servers found for the active connection.") }
        return out
    }
}
