import XCTest
@testable import TessuCore

/// A snapshot full of things that must never reach an AI provider.
enum PrivacyFixture {
    static let ssid = "Villa-Kuusela-5G"
    static let host = "Anttis-MacBook-Pro"
    static let mac = "ce:b8:74:61:6f:89"
    static let publicIp = "88.148.236.160"

    static func snapshot() -> SnapshotInput {
        var wifi = WifiInfo(); wifi.supported = true; wifi.ssid = ssid; wifi.bssid = "24:4b:fe:bd:f6:80"; wifi.channel = 36; wifi.band = .ghz5
        let overview = NetworkOverview(
            hostname: "\(host).local",
            local: .init(ip: "192.168.1.15", iface: "en0", mac: mac, macRandomized: true),
            gateway: .init(ip: "192.168.1.1", mac: "24:4b:fe:bd:f6:80", vendor: "ASUS"),
            publicIp: publicIp, errors: ["lookup for \(publicIp) failed at \(mac)"])
        let devices = [
            Device(ip: "192.168.1.1", mac: "24:4b:fe:bd:f6:80", vendor: "ASUS", randomizedMac: false, isGateway: true, isThisComputer: false, hostname: "router.lan"),
            Device(ip: "192.168.1.8", mac: "70:85:c2:f0:7f:ba", vendor: nil, randomizedMac: false, isGateway: false, isThisComputer: false, hostname: "Lev's-iPhone"),
            Device(ip: "192.168.1.9", mac: "5a:71:4e:52:e2:ca", vendor: nil, randomizedMac: true, isGateway: false, isThisComputer: false, hostname: "Kitchen-Alexa-7F3A"),
        ]
        var survey = WifiSurvey(); survey.supported = true
        survey.networks = [WifiNetwork(ssid: "NeighbourNet-9000", bssid: "de:ad:be:ef:00:01", channel: 6, band: .ghz24, signalPct: 50, rssi: -75, widthMHz: 20)]
        let check = CheckResult(id: "location-map", title: "Wi-Fi location mapping", status: .warn, severity: .low,
                                evidence: "Network \"\(ssid)\" does not end in _nomap", fix: nil)
        let scan = ScanReport(startedAt: Date(), finishedAt: Date(), score: 90, checks: [check], upnpMappings: [], openPorts: [], errors: [])
        let conns = [Connection(process: "Safari", pid: 1, proto: "tcp", local: "192.168.1.15:5000", remoteIp: "17.253.1.1", remotePort: 443, state: "ESTABLISHED")]
        return SnapshotInput(overview: overview, scan: scan, wifi: wifi, survey: survey, devices: devices, connections: conns)
    }
}

final class PromptPrivacyTests: XCTestCase {
    func testNothingIdentifyingLeavesTheMachine() {
        let text = PromptBuilder.userMessage(question: "Is my network safe?", snapshot: PrivacyFixture.snapshot())
        let secrets: [(String, String)] = [
            ("SSID", PrivacyFixture.ssid), ("host name", PrivacyFixture.host), ("own MAC", PrivacyFixture.mac),
            ("gateway MAC", "24:4b:fe:bd:f6:80"), ("public IP", PrivacyFixture.publicIp), ("neighbour SSID", "NeighbourNet-9000"),
            ("neighbour BSSID", "de:ad:be:ef:00:01"), ("device name", "Lev's-iPhone"), ("device name", "Kitchen-Alexa"),
            ("device MAC", "70:85:c2:f0:7f:ba"),
        ]
        for (label, secret) in secrets {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(secret), "\(label) leaked: \(secret)")
        }
    }

    func testWhatIsKeptIsGenericAndUseful() {
        let json = PromptBuilder.minimizeSnapshot(PrivacyFixture.snapshot()).serialized()
        XCTAssertTrue(json.contains("88.148.236.0/24"), "public IP is masked to /24")
        XCTAssertTrue(json.contains("\"kind\":\"iphone\""), "a hostname is reduced to a device kind")
        XCTAssertTrue(json.contains("\"kind\":\"alexa\""))
        XCTAssertTrue(json.contains("\"vendor\":\"ASUS\""))
        XCTAssertTrue(json.contains("[ssid]"), "SSIDs inside free text are replaced, not just dropped")
        XCTAssertTrue(json.contains("\"id\":\"location-map\""))
        XCTAssertTrue(json.contains("\"score\":90"))
    }

    func testPrivacySentenceItselfIsNotScrubbed() {
        var s = PrivacyFixture.snapshot()
        s.overview?.hostname = "privacy-box.local"
        XCTAssertTrue(PromptBuilder.minimizeSnapshot(s).serialized().contains("Removed before sending: full MAC addresses"))
    }

    func testListsAreCappedButTrueTotalsKept() {
        var s = PrivacyFixture.snapshot()
        s.devices = (0..<200).map { Device(ip: "10.0.0.\($0 % 250)", mac: "aa:bb:cc:dd:ee:ff", vendor: "Apple", randomizedMac: false, isGateway: false, isThisComputer: false, hostname: nil) }
        let json = PromptBuilder.minimizeSnapshot(s)
        guard case .array(let items)? = json["devices"]?["items"] else { return XCTFail("devices.items missing") }
        XCTAssertEqual(items.count, Prompt.Limits.devices)
        XCTAssertEqual(json["devices"]?["total"], .number(200))
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(json.serialized().utf8)), "output is valid JSON")
    }

    func testOversizedSnapshotIsTrimmedToFit() {
        var s = PrivacyFixture.snapshot()
        s.connections = (0..<5000).map { Connection(process: "p\($0)", pid: $0, proto: "tcp", local: "1.1.1.1:1", remoteIp: "8.8.\($0 / 250).\($0 % 250)", remotePort: 443, state: "ESTABLISHED") }
        let text = PromptBuilder.minimizeSnapshot(s).serialized()
        XCTAssertLessThanOrEqual(text.count, Prompt.Limits.totalChars)
    }
}
