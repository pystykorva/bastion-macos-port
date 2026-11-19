import Foundation

extension LanHTTP {
    /// Tolerant HTTP response parser: status line, headers, body (chunked or until close).
    static func parse(_ data: Data) -> LanResponse? {
        let crlf = data.range(of: Data("\r\n\r\n".utf8))
        let lf = data.range(of: Data("\n\n".utf8))
        let range = crlf ?? lf
        let headEnd = range?.lowerBound ?? data.endIndex
        let bodyStart = range?.upperBound ?? data.endIndex
        let headText = String(decoding: data[data.startIndex..<headEnd], as: UTF8.self)
        var lines = headText.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let statusLine = lines.first,
              let m = Rx.first("^HTTP/1\\.[01]\\s+(\\d{3})", in: statusLine),
              let status = Int(m[1]) else { return nil }
        lines.removeFirst()
        var headers: [String: String] = [:]
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            let key = l[..<i].trimmingCharacters(in: .whitespaces).lowercased()
            headers[key] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        var bodyData = Data(data[bodyStart...])
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true { bodyData = dechunk(bodyData) }
        return LanResponse(status: status, headers: headers, body: String(decoding: bodyData, as: UTF8.self), error: nil)
    }

    private static func dechunk(_ data: Data) -> Data {
        var out = Data()
        var i = data.startIndex
        while i < data.endIndex {
            guard let nl = data[i...].firstIndex(of: 0x0A) else { break }
            let sizeText = String(decoding: data[i..<nl], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let size = Int(sizeText.split(separator: ";").first ?? "", radix: 16), size > 0 else { break }
            let start = data.index(after: nl)
            let end = data.index(start, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
            out.append(data[start..<end])
            i = data.index(end, offsetBy: 2, limitedBy: data.endIndex) ?? data.endIndex
        }
        return out
    }
}
