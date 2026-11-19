import Foundation

public struct UpnpStatus: Sendable {
    public var found = false
    public var location: String?
    public var server: String?
    public var friendlyName: String?
    public var manufacturer: String?
    public var modelName: String?
    public var externalIp: String?
    public var services: [String] = []
    public var mappings: [UpnpMapping] = []
    /// false when the router would not list its port table at all, so "no mappings" cannot be claimed.
    public var mappingsReadable = true
    public var mappingsProblem: String?
    public var errors: [String] = []
}

struct WanService: Sendable, Equatable {
    var type: String
    var controlUrl: String
}

public enum Upnp {
    static let maxMappings = 64

    static func hostOf(_ url: String) -> String? { URL(string: url)?.host }

    static func resolve(_ base: String, _ rel: String) -> String? {
        URL(string: rel, relativeTo: URL(string: base))?.absoluteURL.absoluteString
    }

    /// WANIPConnection / WANPPPConnection services in a device description. URLBase and controlURL come
    /// from whatever LAN device answered, so a control URL is kept only when it points at the same
    /// private address that served the description (never off the local network).
    static func findWanServices(xml: String, location: String) -> [WanService] {
        let base = XML.tag(xml, "URLBase") ?? location
        let home = hostOf(location)
        var out: [WanService] = []
        for block in XML.blocks(xml, "service") {
            let type = XML.tag(block, "serviceType") ?? ""
            guard Rx.test("WAN(IP|PPP)Connection", type, options: .caseInsensitive) else { continue }
            guard let control = XML.tag(block, "controlURL"), let url = resolve(base, control),
                  let host = hostOf(url), host == home, NetUtil.isPrivateIPv4(host) else { continue }
            out.append(WanService(type: type, controlUrl: url))
        }
        return out
    }

    static func soap(_ service: WanService, _ action: String, _ args: [(String, String)] = []) async -> LanResponse {
        let argXml = args.map { "<\($0.0)>\(XML.escape($0.1))</\($0.0)>" }.joined()
        let body = "<?xml version=\"1.0\"?>\r\n" +
            "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">" +
            "<s:Body><u:\(action) xmlns:u=\"\(service.type)\">\(argXml)</u:\(action)></s:Body></s:Envelope>"
        return await LanHTTP.request(service.controlUrl, method: "POST",
                                     headers: ["Content-Type": "text/xml; charset=\"utf-8\"", "SOAPAction": "\"\(service.type)#\(action)\""],
                                     body: body, timeout: 3)
    }

    /// Walks the router's port-mapping table. A SOAP fault 713 (SpecifiedArrayIndexInvalid) or 714
    /// marks the end of the table; anything else means the list is unreadable or incomplete.
    static func listMappings(_ service: WanService) async -> (mappings: [UpnpMapping], readable: Bool, problem: String?) {
        var mappings: [UpnpMapping] = []
        var readable = true
        var problem: String?
        for i in 0..<maxMappings {
            let res = await soap(service, "GetGenericPortMappingEntry", [("NewPortMappingIndex", String(i))])
            if res.status != 200 {
                let code = res.status == 500 ? XML.tag(res.body, "errorCode") : nil
                if code != "713" && code != "714" {
                    readable = false
                    let why = res.status == 0 ? "no answer (\(res.error ?? "unknown"))" : "UPnP error \(code ?? String(res.status))"
                    problem = i == 0 ? why : "the list stopped after \(i) entr\(i == 1 ? "y" : "ies"): \(why)"
                }
                break
            }
            guard let port = Int(XML.tag(res.body, "NewExternalPort") ?? ""), port > 0 else {
                if i == 0 { readable = false; problem = "the router answered without a readable entry" }
                break
            }
            mappings.append(UpnpMapping(
                proto: (XML.tag(res.body, "NewProtocol") ?? "").uppercased(),
                externalPort: port,
                internalClient: XML.tag(res.body, "NewInternalClient") ?? "",
                internalPort: Int(XML.tag(res.body, "NewInternalPort") ?? ""),
                description: XML.tag(res.body, "NewPortMappingDescription") ?? ""))
        }
        return (mappings, readable, problem)
    }
}
