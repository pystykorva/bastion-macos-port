import Foundation
import Darwin

public struct ArpEntry: Sendable, Equatable {
    public var ip: String
    public var mac: String
    public var iface: String
}

public enum Arp {
    /// "? (192.168.1.1) at a:b:c:d:e:f on en0 ifscope [ethernet]"
    /// "? (192.168.1.7) at (incomplete) on en0 ifscope [ethernet]"  (skipped)
    public static func parse(_ text: String) -> [ArpEntry] {
        var out: [ArpEntry] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let l = String(line)
            guard let m = Rx.first("\\((\\d{1,3}(?:\\.\\d{1,3}){3})\\)\\s+at\\s+([0-9a-f:]+)\\s+on\\s+(\\S+)", in: l, options: .caseInsensitive),
                  let mac = NetUtil.normalizeMac(m[2]) else { continue }
            out.append(ArpEntry(ip: m[1], mac: mac, iface: m[3]))
        }
        return out
    }

    /// ARP neighbours without multicast / broadcast noise.
    public static func read() async -> (entries: [ArpEntry], errors: [String]) {
        let res = await Exec.run("/usr/sbin/arp", ["-an"])
        let errors = res.error.map { [$0] } ?? []
        let entries = parse(res.stdout).filter { e in
            if NetUtil.isMulticastMac(e.mac) { return false }
            if NetUtil.isMulticastIPv4(e.ip) || e.ip == "255.255.255.255" { return false }
            return true
        }
        return (entries, errors)
    }

    /// The ARP table only lists devices this computer talked to recently. One tiny UDP datagram to the
    /// discard port of every address in the local /24 makes the OS resolve each address, so devices
    /// that are present show up. Stays on the local network.
    static func sweepSubnet(ip: String, prefix: Int?, wait: TimeInterval = 2) async {
        guard NetUtil.isPrivateIPv4(ip) else { return }
        let p = max(prefix ?? 24, 24) // never more than 254 hosts
        let net = NetUtil.ipToInt(ip) & NetUtil.prefixToMask(p)
        let count = 1 << (32 - p)
        let hosts = (1..<(count - 1)).map { NetUtil.intToIp(net + UInt32($0)) }.filter { $0 != ip }
        await blocking {
            let fd = socket(AF_INET, SOCK_DGRAM, 0)
            guard fd >= 0 else { return }
            defer { close(fd) }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            var payload: UInt8 = 0
            for host in hosts {
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = UInt16(9).bigEndian
                inet_pton(AF_INET, host, &addr.sin_addr)
                withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        _ = sendto(fd, &payload, 1, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                usleep(1500) // pace the burst so the ARP queue is not flooded
            }
        }
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
    }
}
