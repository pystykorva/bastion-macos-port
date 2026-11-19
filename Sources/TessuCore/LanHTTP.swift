import Foundation
import Darwin

public struct LanResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: String
    public var error: String?

    static func failure(_ why: String) -> LanResponse { LanResponse(status: 0, headers: [:], body: "", error: why) }
}

/// Plain HTTP for talking to devices on the local network. Routers often send slightly malformed
/// HTTP, which URLSession rejects, so this is a small tolerant client over a BSD socket.
/// Only literal private IPv4 hosts are allowed: nothing here can leave the local network.
public enum LanHTTP {
    public static func request(
        _ urlString: String, method: String = "GET", headers: [String: String] = [:], body: String? = nil,
        timeout: TimeInterval = 3, maxBytes: Int = 2 << 20
    ) async -> LanResponse {
        guard let url = URL(string: urlString), let host = url.host else {
            return .failure("Invalid URL: \(urlString)")
        }
        guard url.scheme == "http" else {
            return .failure("Only plain HTTP on the local network is supported: \(urlString)")
        }
        guard NetUtil.isPrivateIPv4(host) else {
            return .failure("Refused a request outside the local network: \(urlString)")
        }
        var path = url.path.isEmpty ? "/" : url.path
        if let q = url.query { path += "?" + q }
        let port = url.port ?? 80
        var head = "\(method) \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nConnection: close\r\n"
        var all = headers
        let payload = body.map { Array($0.utf8) } ?? []
        if body != nil { all["Content-Length"] = String(payload.count) }
        for (k, v) in all { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        let bytes = Array(head.utf8) + payload
        let deadline = Date().addingTimeInterval(timeout)
        let label = "HTTP \(method) \(urlString)"
        return await blocking {
            exchange(host: host, port: port, request: bytes, deadline: deadline, maxBytes: maxBytes, label: label)
        }
    }

    private static func remainingMs(_ deadline: Date) -> Int32 { Int32(max(0, deadline.timeIntervalSinceNow * 1000)) }

    private static func connectSocket(host: String, port: Int, deadline: Date) -> (fd: Int32, error: String?) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return (-1, "no socket") }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)
        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if rc == 0 { return (fd, nil) }
        guard errno == EINPROGRESS else { let e = errno; close(fd); return (-1, "connection failed (errno \(e))") }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, 1, remainingMs(deadline)) > 0 else { close(fd); return (-1, "timed out") }
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        if err != 0 { close(fd); return (-1, "connection failed (errno \(err))") }
        return (fd, nil)
    }

    private static func exchange(host: String, port: Int, request: [UInt8], deadline: Date, maxBytes: Int, label: String) -> LanResponse {
        let conn = connectSocket(host: host, port: port, deadline: deadline)
        guard conn.fd >= 0 else { return .failure("\(label): \(conn.error ?? "failed")") }
        let fd = conn.fd
        defer { close(fd) }

        var sent = 0
        while sent < request.count {
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&pfd, 1, remainingMs(deadline)) > 0 else { return .failure("\(label): timed out") }
            let n = request[sent...].withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            if n > 0 { sent += n } else if n < 0 && errno != EAGAIN && errno != EINTR { return .failure("\(label): send failed") }
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, remainingMs(deadline))
            if ready == 0 { if data.isEmpty { return .failure("\(label): timed out") } else { break } }
            if ready < 0 { if errno == EINTR { continue }; break }
            let n = recv(fd, &buffer, buffer.count, 0)
            if n > 0 {
                if data.count < maxBytes { data.append(contentsOf: buffer[0..<n]) }
            } else if n == 0 || (errno != EAGAIN && errno != EINTR) {
                break
            }
        }
        return parse(data) ?? .failure("\(label): the device sent no readable HTTP answer")
    }
}
