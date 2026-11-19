import Foundation
import Darwin

public struct SsdpResponse: Sendable, Hashable {
    public var from: String
    public var location: String
    public var st: String
    public var server: String
    public var usn: String
}

public enum Ssdp {
    static let group = "239.255.255.250"
    static let port: UInt16 = 1900
    static let targets = [
        "urn:schemas-upnp-org:device:InternetGatewayDevice:1",
        "urn:schemas-upnp-org:device:InternetGatewayDevice:2",
        "ssdp:all",
    ]

    static func mSearch(_ st: String) -> [UInt8] {
        Array(("M-SEARCH * HTTP/1.1\r\nHOST: \(group):\(port)\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(st)\r\n" +
               "USER-AGENT: Tessu/1.0 UPnP/1.1\r\n\r\n").utf8)
    }

    static func parseHeaders(_ text: String) -> [String: String] {
        var h: [String: String] = [:]
        for line in text.components(separatedBy: .newlines).dropFirst() {
            guard let i = line.firstIndex(of: ":"), i != line.startIndex else { continue }
            h[line[..<i].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        return h
    }

    /// Sends M-SEARCH to the multicast group and straight to the gateway, collects answers for `wait`
    /// seconds, de-duplicated by LOCATION. Never throws: socket problems come back in `errors`.
    public static func search(localIp: String?, gatewayIp: String?, wait: TimeInterval = 2.5) async -> (responses: [SsdpResponse], errors: [String]) {
        await blocking { searchSync(localIp: localIp, gatewayIp: gatewayIp, wait: wait) }
    }

    private static func sendTo(_ fd: Int32, _ bytes: [UInt8], host: String) {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                _ = sendto(fd, bytes, bytes.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    private static func searchSync(localIp: String?, gatewayIp: String?, wait: TimeInterval) -> (responses: [SsdpResponse], errors: [String]) {
        var errors: [String] = []
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return ([], ["SSDP socket failed (errno \(errno))"]) }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &bindAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if bound != 0 { return ([], ["SSDP bind failed (errno \(errno))"]) }

        if let ip = localIp {
            var iface = in_addr()
            if inet_pton(AF_INET, ip, &iface) == 1 { setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &iface, socklen_t(MemoryLayout<in_addr>.size)) }
        }
        var ttl: UInt8 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        func sendAll() {
            for st in targets {
                let packet = mSearch(st)
                sendTo(fd, packet, host: group)
                if let gw = gatewayIp { sendTo(fd, packet, host: gw) }
            }
        }
        sendAll()
        let start = Date()
        var resent = false
        var found: [String: SsdpResponse] = [:]
        var buffer = [UInt8](repeating: 0, count: 8192)
        while Date().timeIntervalSince(start) < wait {
            if !resent && Date().timeIntervalSince(start) > 0.7 { sendAll(); resent = true } // UDP gets lost; ask twice
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, 100)
            if ready <= 0 { continue }
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &fromLen) }
            }
            guard n > 0 else { continue }
            let text = String(decoding: buffer[0..<n], as: UTF8.self)
            guard Rx.test("^(HTTP/1\\.[01]\\s+200|NOTIFY)", text, options: .caseInsensitive) else { continue }
            let h = parseHeaders(text)
            guard let location = h["location"], !location.isEmpty else { continue }
            var a = from.sin_addr
            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &a, &ipBuf, socklen_t(INET_ADDRSTRLEN))
            if found[location] == nil {
                found[location] = SsdpResponse(from: String(cString: ipBuf), location: location, st: h["st"] ?? h["nt"] ?? "",
                                               server: h["server"] ?? "", usn: h["usn"] ?? "")
            }
        }
        if found.isEmpty && errors.isEmpty { errors = [] }
        return (Array(found.values), errors)
    }
}
