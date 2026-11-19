import Foundation

/// This computer's live network connections, from `lsof -nP -i`. Without administrator rights macOS
/// only lists connections of apps run by the current user, and the result says so.
public enum Connections {
    static func splitEndpoint(_ text: String) -> (addr: String, port: Int) {
        let t = text.trimmingCharacters(in: .whitespaces)
        let m = Rx.first("^\\[(.*)\\]:(\\d+|\\*)$", in: t) ?? Rx.first("^(.*):(\\d+|\\*)$", in: t)
        guard let g = m else { return (t, 0) }
        let addr = g[1].replacingOccurrences(of: "%\\w+$", with: "", options: .regularExpression)
        return (addr, g[2] == "*" ? 0 : Int(g[2]) ?? 0)
    }

    static func formatLocal(_ addr: String, _ port: Int) -> String {
        addr.contains(":") ? "[\(addr)]:\(port)" : "\(addr):\(port)"
    }

    /// COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
    /// "Google\x20Chrome 512 me 23u IPv4 0x.. 0t0 TCP 192.168.1.5:52341->142.250.74.14:443 (ESTABLISHED)"
    public static func parseLsof(_ text: String) -> [Connection] {
        var out: [Connection] = []
        var seen = Set<String>()
        let pattern = "^(\\S+)\\s+(\\d+)\\s+\\S+\\s+\\S+\\s+(IPv4|IPv6)\\s+\\S+\\s+\\S+\\s+(TCP|UDP)\\s+(\\S+)(?:\\s+\\((\\w+)\\))?"
        for line in text.split(whereSeparator: \.isNewline).dropFirst() {
            guard let m = Rx.first(pattern, in: String(line)), let pid = Int(m[2]) else { continue }
            let process = unescape(m[1])
            let proto = m[4].lowercased()
            let parts = m[5].components(separatedBy: "->")
            let l = splitEndpoint(parts[0])
            let state = m[6].isEmpty ? nil : m[6].uppercased()
            var item: Connection
            if proto == "tcp" {
                guard state == "ESTABLISHED" || state == "LISTEN" else { continue }
                if state == "LISTEN" || parts.count < 2 {
                    if NetUtil.isLoopback(l.addr) { continue }
                    item = Connection(process: process, pid: pid, proto: proto, local: formatLocal(l.addr, l.port),
                                      remoteIp: "*", remotePort: 0, state: "LISTEN")
                } else {
                    let r = splitEndpoint(parts[1])
                    if NetUtil.isLoopback(l.addr) || NetUtil.isLoopback(r.addr) { continue }
                    item = Connection(process: process, pid: pid, proto: proto, local: formatLocal(l.addr, l.port),
                                      remoteIp: r.addr, remotePort: r.port, state: "ESTABLISHED")
                }
            } else {
                if NetUtil.isLoopback(l.addr) { continue }
                let r = parts.count > 1 ? splitEndpoint(parts[1]) : (addr: "*", port: 0)
                if NetUtil.isLoopback(r.addr) { continue }
                item = Connection(process: process, pid: pid, proto: proto, local: formatLocal(l.addr, l.port),
                                  remoteIp: r.addr.isEmpty ? "*" : r.addr, remotePort: r.port, state: nil)
            }
            if seen.insert(item.id).inserted { out.append(item) }
        }
        return out
    }

    /// lsof escapes unusual bytes in command names as \xNN ("Google\x20Chrome").
    static func unescape(_ s: String) -> String {
        var out = s
        for m in Rx.all("\\\\x([0-9a-fA-F]{2})", in: s) {
            if let n = UInt32(m[1], radix: 16), let u = Unicode.Scalar(n) {
                out = out.replacingOccurrences(of: m[0], with: String(Character(u)))
            }
        }
        return out
    }

    public static func list() async -> ConnectionList {
        var errors: [String] = []
        let res = await Exec.run("/usr/sbin/lsof", ["-nP", "+c", "0", "-i"], timeout: 12) // +c 0: full names, lsof cuts them to 9 characters
        // lsof exits with 1 when it finds nothing; only report real failures.
        if let e = res.error, res.stdout.isEmpty { errors.append(e) }
        if getuid() != 0 {
            errors.append("Partial list: without administrator rights macOS only shows connections of apps run by the current user.")
        }
        return ConnectionList(items: parseLsof(res.stdout), errors: errors)
    }
}
