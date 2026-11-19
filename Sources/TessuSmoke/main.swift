import Foundation
import TessuCore

// Runs the real engine against the real network. Usage: tessu-smoke [overview|devices|scan|wifi|dns|connections|speed|all]
setvbuf(stdout, nil, _IOLBF, 0)
let want = Set(CommandLine.arguments.dropFirst())
func on(_ k: String) -> Bool { want.isEmpty || want.contains(k) || want.contains("all") }
func section(_ t: String) { print("\n=== \(t) ===") }
func time<T>(_ body: () async -> T) async -> (T, Double) {
    let t0 = Date(); let v = await body(); return (v, Date().timeIntervalSince(t0))
}

if on("overview") {
    section("overview")
    let (o, s) = await time { await Overview.overview() }
    print("host \(o.hostname) | local \(o.local.ip) \(o.local.iface) \(o.local.mac) random=\(String(describing: o.local.macRandomized))")
    print("gateway \(o.gateway.ip ?? "nil") mac=\(o.gateway.mac ?? "nil") vendor=\(o.gateway.vendor ?? "nil")")
    print("public \(o.publicIp ?? "nil")  errors=\(o.errors)  (\(String(format: "%.1f", s)) s)")
}
if on("devices") {
    section("devices")
    let (d, s) = await time { await Devices.discover() }
    for x in d.devices { print("\(x.ip.padding(toLength: 16, withPad: " ", startingAt: 0)) \(x.mac) vendor=\(x.vendor ?? "-") rand=\(x.randomizedMac) gw=\(x.isGateway) me=\(x.isThisComputer) name=\(x.hostname ?? "-")") }
    print("\(d.devices.count) devices errors=\(d.errors) (\(String(format: "%.1f", s)) s)")
}
if on("wifi") {
    section("wifi")
    let w = await Wifi.info()
    print("supported=\(w.supported) ssid=\(w.ssid ?? "nil") bssid=\(w.bssid ?? "nil") band=\(w.band?.rawValue ?? "nil") ch=\(w.channel.map(String.init) ?? "nil") width=\(w.widthMHz.map(String.init) ?? "nil") rssi=\(w.rssi.map(String.init) ?? "nil") pct=\(w.signalPct.map(String.init) ?? "nil") rate=\(w.rxMbps.map { String($0) } ?? "nil") sec=\(w.security ?? "nil")")
    print("errors=\(w.errors)")
    let (sv, s) = await time { await Wifi.survey() }
    print("survey supported=\(sv.supported) networks=\(sv.networks.count) own=\(sv.networks.filter(\.own).count) (\(String(format: "%.1f", s)) s)")
    for n in sv.networks.prefix(8) { print("  ch \(n.channel) \(n.band.rawValue)GHz \(n.signalPct.map(String.init) ?? "-")% own=\(n.own) w=\(n.widthMHz.map(String.init) ?? "-") ssid='\(n.ssid)'") }
    print("recommendation: \(sv.recommendation?.reason ?? "none")")
    print("errors=\(sv.errors)")
}
if on("dns") {
    section("dns")
    let d = await Dns.status()
    print("servers=\(d.servers) provider=\(d.provider ?? "nil") gwResolver=\(d.gatewayIsResolver) encrypted=\(String(describing: d.encrypted)) errors=\(d.errors)")
}
if on("connections") {
    section("connections")
    let c = await Connections.list()
    for x in c.items.prefix(8) { print("\(x.process ?? "?") \(x.proto) \(x.local) -> \(x.remoteIp):\(x.remotePort) \(x.state ?? "")") }
    print("\(c.items.count) connections errors=\(c.errors)")
}
if on("scan") {
    section("scan")
    let (r, s) = await time { await Scan.run { p in if let st = p.status { print("  [\(p.index + 1)/\(p.total)] \(p.id): \(st.rawValue)") } } }
    print("score \(r.score)  open ports \(r.openPorts.map { $0.port })  upnp mappings \(r.upnpMappings.count)  (\(String(format: "%.1f", s)) s)")
    for c in r.checks { print("- [\(c.status.rawValue)/\(c.severity.rawValue)] \(c.title)\n    \(c.evidence)") }
    print("errors: \(r.errors)")
}
if want.contains("speed") || want.contains("all") {
    section("speed")
    var lastPhase = ""
    let r = await SpeedTest.run { p in
        if p.phase.rawValue != lastPhase { lastPhase = p.phase.rawValue; print("  phase \(lastPhase)") }
    }
    print("ping \(r.pingMs.map { String($0) } ?? "nil") ms jitter \(r.jitterMs.map { String($0) } ?? "nil") down \(r.downMbps.map { String($0) } ?? "nil") up \(r.upMbps.map { String($0) } ?? "nil") server \(r.server)")
    print("errors=\(r.errors)")
}

// tessu-smoke local [url] [question...]: a real question to a local OpenAI-style server, through the app's own code.
if want.contains("local") {
    section("local server")
    let args = Array(CommandLine.arguments.dropFirst().drop { $0 != "local" }.dropFirst())
    let url = args.first ?? LocalServer.defaultURL
    let question = args.dropFirst().joined(separator: " ")
    let agents = Agents(keystore: Keystore(defaults: UserDefaults(suiteName: "tessu.smoke")!, inMemory: true))
    print("address check:", agents.setLocalAddress(url) ?? "ok")
    if let sfx = ProcessInfo.processInfo.environment["TESSU_LOCAL_SUFFIX"] { agents.keystore.localSuffix = sfx }
    let models = await agents.localModels()
    print("models:", models.models, models.error ?? "")
    let t0 = Date()
    let test = await agents.test(.local)
    print("test:", test.ok ? "works, model \(test.model)" : (test.error ?? "failed"), String(format: "(%.1f s)", Date().timeIntervalSince(t0)))
    if !question.isEmpty {
        let scan = await Scan.run()
        let snap = SnapshotInput(overview: await Overview.overview(), scan: scan, wifi: await Wifi.info(), dns: await Dns.status(), devices: (await Devices.discover()).devices)
        let full = PromptBuilder.minimizeSnapshot(snap).serialized().count
        let compact = PromptBuilder.compactSnapshot(snap).serialized().count
        print("snapshot chars: full \(full), compact \(compact)")
        let t1 = Date()
        let r = await agents.ask(.local, question: question, snapshot: snap)
        print(String(format: "answer in %.1f s, ok=%@, model=%@", Date().timeIntervalSince(t1), String(r.ok), r.model))
        print(r.ok ? r.text : (r.error ?? "no error text"))
    }
}
