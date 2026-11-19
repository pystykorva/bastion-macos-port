import Foundation

extension Scan {
    /// Runs every check. All data sources start at once; each check awaits only what it needs, so the
    /// progress callback ticks through the list as results become available.
    public static func run(onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) async -> ScanReport {
        let startedAt = Date()
        let route = await SystemInfo.defaultRoute()
        var errors = route.errors
        let gw = route.gateway

        async let portsTask: PortProbeResult? = gw == nil ? nil : await Ports.probeGateway(gw)
        async let upnpTask = Upnp.status(localIp: route.ip, gatewayIp: gw)
        async let dnsTask = Dns.status()
        async let wifiTask = Wifi.info()
        async let adapterTask = Overview.wifiAdapter()
        async let devicesTask = Devices.discover()

        var ctx = ScanContext(gw: gw, route: route)
        var results: [CheckResult] = []
        let total = checks.count

        for (index, def) in checks.enumerated() {
            onProgress(ScanProgress(index: index, total: total, id: def.id, title: def.title, status: nil))
            let r: CheckResult
            switch def.id {
            case "tr069": ctx.ports = await portsTask; r = tr069(ctx)
            case "upnp": ctx.upnp = await upnpTask; r = upnp(ctx)
            case "dns-plaintext": ctx.dns = await dnsTask; r = dns(ctx)
            case "admin-default": ctx.ports = await portsTask; r = adminDefault(ctx)
            case "wps": r = wps(ctx)
            case "telnet": ctx.ports = await portsTask; r = telnet(ctx)
            case "ssh": ctx.ports = await portsTask; r = ssh(ctx)
            case "web-admin-http": ctx.ports = await portsTask; r = webAdmin(ctx)
            case "location-map": ctx.wifi = await wifiTask; r = locationMap(ctx)
            case "mac-privacy": ctx.wifiAdapter = await adapterTask; r = macPrivacy(ctx)
            case "wifi-security": ctx.wifi = await wifiTask; r = wifiSecurity(ctx)
            case "unknown-devices": ctx.devices = await devicesTask; r = unknownDevices(ctx)
            default: r = result(def.id, .unknown, .info, "This check is not available.")
            }
            results.append(r)
            onProgress(ScanProgress(index: index, total: total, id: def.id, title: r.title, status: r.status))
        }

        let ports = await portsTask
        let upnp = await upnpTask
        errors.append(contentsOf: ports?.errors ?? [])
        errors.append(contentsOf: upnp.errors)
        errors.append(contentsOf: (await dnsTask).errors)
        errors.append(contentsOf: (await wifiTask).errors)
        errors.append(contentsOf: (await adapterTask).errors)
        errors.append(contentsOf: (await devicesTask).errors)

        var seen = Set<String>()
        let unique = errors.filter { seen.insert($0).inserted }
        return ScanReport(startedAt: startedAt, finishedAt: Date(), score: score(results), checks: results,
                          upnpMappings: upnp.mappings, openPorts: ports?.open ?? [], errors: unique)
    }
}
