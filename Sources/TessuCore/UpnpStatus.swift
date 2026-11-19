import Foundation

extension Upnp {
    /// Finds the router's Internet Gateway Device and reads which ports devices opened to the internet.
    /// Read-only: it only lists the table, it never adds or removes a mapping.
    public static func status(localIp: String?, gatewayIp: String?) async -> UpnpStatus {
        var result = UpnpStatus()
        let search = await Ssdp.search(localIp: localIp, gatewayIp: gatewayIp)
        result.errors.append(contentsOf: search.errors)

        // Only descriptions served from the local network; prefer the gateway's own answer.
        let candidates = search.responses
            .filter { NetUtil.isPrivateIPv4(hostOf($0.location)) }
            .sorted { a, b in
                let ga = a.from == gatewayIp, gb = b.from == gatewayIp
                if ga != gb { return ga }
                return Rx.test("InternetGatewayDevice", a.st) && !Rx.test("InternetGatewayDevice", b.st)
            }

        for c in candidates.prefix(12) {
            let desc = await LanHTTP.request(c.location, timeout: 3)
            guard desc.status == 200, Rx.test("InternetGatewayDevice", desc.body, options: .caseInsensitive) else { continue }
            let services = findWanServices(xml: desc.body, location: c.location)
            result.found = true
            result.location = c.location
            result.server = c.server.isEmpty ? nil : c.server
            result.friendlyName = XML.tag(desc.body, "friendlyName")
            result.manufacturer = XML.tag(desc.body, "manufacturer")
            result.modelName = XML.tag(desc.body, "modelName")
            result.services = services.map(\.type)
            if services.isEmpty {
                result.mappingsReadable = false
                result.mappingsProblem = "the router did not describe a WAN connection service on its own address"
            }
            var seen = Set<String>()
            var anyReadable = false
            for s in services {
                let ext = await soap(s, "GetExternalIPAddress")
                if ext.status == 200, result.externalIp == nil { result.externalIp = XML.tag(ext.body, "NewExternalIPAddress") }
                let maps = await listMappings(s)
                // WANIPConnection and WANPPPConnection often share one table: list each mapping once.
                for m in maps.mappings where seen.insert("\(m.proto)|\(m.externalPort)").inserted {
                    result.mappings.append(m)
                }
                if maps.readable { anyReadable = true } else if result.mappingsProblem == nil { result.mappingsProblem = maps.problem }
            }
            if !services.isEmpty { result.mappingsReadable = anyReadable }
            if anyReadable { result.mappingsProblem = nil }
            break
        }
        return result
    }
}
