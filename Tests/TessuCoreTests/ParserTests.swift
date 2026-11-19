import XCTest
@testable import TessuCore

func fixture(_ name: String) throws -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
        throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}

final class ParserTests: XCTestCase {
    func testArpParsing() throws {
        let entries = Arp.parse(try fixture("arp.txt"))
        XCTAssertEqual(entries.count, 7, "the (incomplete) entry is skipped")
        XCTAssertEqual(entries.first, ArpEntry(ip: "192.168.1.1", mac: "24:4b:fe:bd:f6:80", iface: "en0"))
        XCTAssertEqual(entries.first { $0.ip == "192.168.1.117" }?.mac, "88:70:15:00:44:10")
        XCTAssertNil(entries.first { $0.ip == "192.168.1.7" })
        XCTAssertEqual(entries.last?.iface, "bridge100")
    }

    func testLsofParsing() throws {
        let list = Connections.parseLsof(try fixture("lsof.txt"))
        let chrome = list.filter { $0.process == "Google Chrome" }
        XCTAssertEqual(chrome.count, 2, "\\x20 in the command name is decoded")
        XCTAssertEqual(chrome.first?.remoteIp, "142.250.74.14")
        XCTAssertEqual(chrome.first?.remotePort, 443)
        XCTAssertEqual(chrome.first?.state, "ESTABLISHED")
        XCTAssertTrue(list.contains { $0.process == "rapportd" && $0.state == "LISTEN" && $0.local == "*:60099" })
        XCTAssertFalse(list.contains { $0.process == "node" }, "loopback-only sockets are dropped")
        XCTAssertFalse(list.contains { $0.process == "curl" }, "SYN_SENT is neither ESTABLISHED nor LISTEN")
        XCTAssertTrue(list.contains { $0.process == "mDNSResponder" && $0.proto == "udp" })
        let v6 = list.first { $0.process == "identitys" }
        XCTAssertEqual(v6?.remoteIp, "fe80:17::8ee6")
        XCTAssertEqual(v6?.remotePort, 1028)
    }

    func testScutilSkipsPerDomainResolvers() throws {
        let servers = Dns.parseScutil(try fixture("scutil.txt"))
        XCTAssertEqual(servers, ["8.8.8.8", "208.67.220.220", "192.168.1.1"], "scoped queries and .local resolvers are ignored")
    }

    func testDnsProvider() {
        XCTAssertEqual(Dns.provider(for: ["1.1.1.1"], gateway: "192.168.1.1"), "Cloudflare")
        XCTAssertEqual(Dns.provider(for: ["192.168.1.1"], gateway: "192.168.1.1"), "ISP / router")
        XCTAssertEqual(Dns.provider(for: ["203.0.113.5"], gateway: "192.168.1.1"), "Other (probably your provider)")
        XCTAssertNil(Dns.provider(for: [], gateway: nil))
    }

    func testRouteParsing() {
        let text = "   route to: default\ndestination: default\n       mask: default\n    gateway: 192.168.1.1\n  interface: en0\n"
        let r = SystemInfo.parseRouteGet(text)
        XCTAssertEqual(r.gateway, "192.168.1.1")
        XCTAssertEqual(r.iface, "en0")
        XCTAssertNil(SystemInfo.parseRouteGet("gateway: link#14\ninterface: en0").gateway, "a non-IPv4 gateway is not a gateway")
    }

    func testIgdParsingKeepsOnlySameHostServices() throws {
        let xml = try fixture("igd.xml")
        let services = Upnp.findWanServices(xml: xml, location: "http://192.168.1.1:5000/rootDesc.xml")
        XCTAssertEqual(services.count, 1, "an off-network controlURL and non-WAN services are dropped")
        XCTAssertEqual(services.first?.controlUrl, "http://192.168.1.1:5000/ctl/IPConn")
        XCTAssertEqual(XML.tag(xml, "manufacturer"), "Acme & Sons", "entities are decoded")
        XCTAssertEqual(XML.tag(xml, "modelName"), "AX-1")
    }

    func testXmlHelpers() {
        XCTAssertEqual(XML.tag("<s:Body><u:NewPort>8080</u:NewPort></s:Body>", "NewPort"), "8080", "namespace prefix tolerated")
        XCTAssertEqual(XML.decode("&amp;lt;"), "&lt;", "&amp; is decoded last")
        XCTAssertEqual(XML.decode("<![CDATA[a < b]]>"), "a < b")
        XCTAssertEqual(XML.blocks("<a>1</a><a>2</a>", "a"), ["1", "2"])
        XCTAssertEqual(XML.escape("a<b>&\"c"), "a&lt;b&gt;&amp;&quot;c")
    }

    func testHttpParsingToleratesChunkedAndBareNewlines() {
        let chunked = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nX-A: b\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"
        let r = LanHTTP.parse(Data(chunked.utf8))
        XCTAssertEqual(r?.status, 200)
        XCTAssertEqual(r?.body, "hello world")
        XCTAssertEqual(r?.headers["x-a"], "b")
        let sloppy = LanHTTP.parse(Data("HTTP/1.0 500 Oops\n\nfault".utf8))
        XCTAssertEqual(sloppy?.status, 500)
        XCTAssertEqual(sloppy?.body, "fault")
        XCTAssertNil(LanHTTP.parse(Data("garbage".utf8)))
    }

    func testLanHttpRefusesPublicAndNonHttpTargets() async {
        let pub = await LanHTTP.request("http://8.8.8.8/")
        XCTAssertEqual(pub.status, 0)
        XCTAssertTrue(pub.error?.contains("outside the local network") == true)
        let tls = await LanHTTP.request("https://192.168.1.1/")
        XCTAssertTrue(tls.error?.contains("Only plain HTTP") == true)
        let name = await LanHTTP.request("http://example.com/")
        XCTAssertNotNil(name.error, "host names are refused, only literal private IPs pass")
    }
}
