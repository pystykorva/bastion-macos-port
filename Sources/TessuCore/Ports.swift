import Foundation
import Darwin

public enum PortState: String, Sendable {
    case open, closed, filtered
}

public struct PortProbeResult: Sendable {
    public var open: [OpenPort]
    public var results: [Int: PortState]
    public var errors: [String]

    public init(open: [OpenPort] = [], results: [Int: PortState] = [:], errors: [String] = []) {
        self.open = open; self.results = results; self.errors = errors
    }

    /// True when the router answered none of the probes. Then "not open" proves nothing: a VPN
    /// kill-switch, client isolation or a drop-all firewall looks the same.
    public var routerSilent: Bool {
        !results.isEmpty && results.values.allSatisfy { $0 == .filtered }
    }
}

public enum Ports {
    /// TCP ports probed on the router. UDP services (UPnP SSDP on 1900) are covered by UPnP.
    public static let gatewayPorts: [OpenPort] = [
        OpenPort(port: 21, service: "FTP"),
        OpenPort(port: 22, service: "SSH"),
        OpenPort(port: 23, service: "Telnet"),
        OpenPort(port: 53, service: "DNS"),
        OpenPort(port: 80, service: "HTTP (admin page)"),
        OpenPort(port: 443, service: "HTTPS (admin page)"),
        OpenPort(port: 4567, service: "TR-069 (provider management, alternate)"),
        OpenPort(port: 5000, service: "UPnP / web service"),
        OpenPort(port: 7547, service: "TR-069 / CWMP (provider remote management)"),
        OpenPort(port: 8080, service: "HTTP (alternate admin)"),
        OpenPort(port: 8291, service: "MikroTik Winbox"),
        OpenPort(port: 8443, service: "HTTPS (alternate admin)"),
        OpenPort(port: 9000, service: "Web service"),
        OpenPort(port: 30005, service: "TR-069 (provider management, alternate)"),
        OpenPort(port: 49152, service: "UPnP control"),
        OpenPort(port: 52869, service: "UPnP (Realtek SDK)"),
    ]

    /// One TCP connect attempt: open (connected), closed (refused) or filtered (no answer / error).
    public static func probe(host: String, port: Int, timeout: TimeInterval = 0.9) async -> PortState {
        await blocking { probeSync(host: host, port: port, timeoutMs: Int32(timeout * 1000)) }
    }

    static func probeSync(host: String, port: Int, timeoutMs: Int32) -> PortState {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return .filtered }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return .filtered }

        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc == 0 { return .open }
        if errno == ECONNREFUSED { return .closed }
        guard errno == EINPROGRESS else { return .filtered }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let n = poll(&pfd, 1, timeoutMs)
        if n <= 0 { return .filtered }
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        if err == 0 { return .open }
        return err == ECONNREFUSED ? .closed : .filtered
    }

    public static func probeGateway(_ host: String?, list: [OpenPort] = gatewayPorts) async -> PortProbeResult {
        guard let host = host, NetUtil.isIPv4(host) else {
            return PortProbeResult(errors: ["No gateway address, so router ports were not probed."])
        }
        let states = await mapLimit(list.map(\.port), limit: 16) { port in (port, await probe(host: host, port: port)) }
        var results: [Int: PortState] = [:]
        for (port, state) in states { results[port] = state }
        let open = list.filter { results[$0.port] == .open }
        return PortProbeResult(open: open, results: results)
    }
}
