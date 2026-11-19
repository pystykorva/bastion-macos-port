import XCTest
@testable import TessuCore

func wnet(_ ch: Int, _ band: WifiBand, pct: Int = 60, width: Int? = nil, bssid: String? = nil, ssid: String = "", own: Bool = false) -> WifiNetwork {
    WifiNetwork(ssid: ssid, bssid: bssid, channel: ch, band: band, signalPct: pct, rssi: nil, widthMHz: width, own: own)
}

final class WifiLogicTests: XCTestCase {
    func testOccupiedChannels5GHz() {
        XCTAssertEqual(WifiLogic.occupied5(36, width: 20), [36])
        XCTAssertEqual(WifiLogic.occupied5(36, width: nil), [36])
        XCTAssertEqual(WifiLogic.occupied5(40, width: 40), [36, 40])
        XCTAssertEqual(WifiLogic.occupied5(48, width: 80), [36, 40, 44, 48])
        XCTAssertEqual(WifiLogic.occupied5(44, width: 160), [36, 40, 44, 48, 52, 56, 60, 64])
        XCTAssertEqual(WifiLogic.occupied5(149, width: 80), [149, 153, 157, 161])
    }

    func testOverlapRules() {
        XCTAssertTrue(WifiLogic.overlaps(.ghz24, 1, nil, 4, nil), "2.4 GHz channels within 4 overlap")
        XCTAssertFalse(WifiLogic.overlaps(.ghz24, 1, nil, 6, nil))
        XCTAssertTrue(WifiLogic.overlaps(.ghz5, 36, 80, 48, 20), "a 80 MHz block covers 36..48")
        XCTAssertFalse(WifiLogic.overlaps(.ghz5, 36, 20, 40, 20))
    }

    func testSiblingBssid() {
        // Another radio of the same router: next address in the same block of 8.
        XCTAssertTrue(WifiLogic.siblingBssid("8c:90:2d:37:09:70", "8c:90:2d:37:09:72"))
        // Guest / hidden BSSID derived with the locally-administered bit (the example from the original comments).
        XCTAssertTrue(WifiLogic.siblingBssid("8c:90:2d:37:09:7e", "8e:90:2d:77:09:7c"))
        // A neighbour with the same OUI but a different device is not a sibling.
        XCTAssertFalse(WifiLogic.siblingBssid("8c:90:2d:37:09:70", "8c:90:2d:55:aa:70"))
        XCTAssertFalse(WifiLogic.siblingBssid("8c:90:2d:37:09:70", "8c:90:2d:37:09:70"), "identical is not a sibling")
        XCTAssertFalse(WifiLogic.siblingBssid(nil, "8c:90:2d:37:09:70"))
    }

    func testMarkOwnByBssidSsidAndSibling() {
        var info = WifiInfo(); info.bssid = "8c:90:2d:37:09:70"; info.ssid = "Home"
        var list = [
            wnet(6, .ghz24, bssid: "8c:90:2d:37:09:70"),
            wnet(11, .ghz24, bssid: "11:22:33:44:55:66", ssid: "Home"),
            wnet(36, .ghz5, bssid: "8c:90:2d:37:09:72"),
            wnet(1, .ghz24, bssid: "de:ad:be:ef:00:01", ssid: "Neighbour"),
        ]
        WifiLogic.markOwn(&list, info: info)
        XCTAssertEqual(list.map(\.own), [true, true, true, false])
    }

    func testCongestionCountsOnlyForeignNetworks() {
        let networks = [wnet(6, .ghz24), wnet(6, .ghz24), wnet(11, .ghz24, own: true), wnet(1, .ghz24)]
        let c = WifiLogic.buildCongestion(networks, currentBand: .ghz24, currentChannel: 11)
        XCTAssertEqual(c.first { $0.channel == 6 }?.count, 2)
        XCTAssertEqual(c.first { $0.channel == 11 }?.count, 0, "own router never competes with itself")
        XCTAssertEqual(c.first { $0.channel == 1 }?.count, 1)
        XCTAssertEqual(c.map(\.channel), c.map(\.channel).sorted(), "sorted by channel within a band")
    }

    func testDedupeKeepsStrongestAndOwn() {
        let a = wnet(6, .ghz24, pct: 40, bssid: "aa:aa:aa:aa:aa:aa")
        let b = wnet(6, .ghz24, pct: 80, bssid: "aa:aa:aa:aa:aa:aa")
        let own = wnet(6, .ghz24, pct: 10, bssid: "bb:bb:bb:bb:bb:bb", own: true)
        let out = WifiLogic.dedupe([a, b, own, wnet(6, .ghz24, pct: 5, bssid: "bb:bb:bb:bb:bb:bb")])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.first { $0.bssid == "aa:aa:aa:aa:aa:aa" }?.signalPct, 80)
        XCTAssertEqual(out.first { $0.bssid == "bb:bb:bb:bb:bb:bb" }?.own, true)
    }

    func testHelpers() {
        XCTAssertEqual(WifiLogic.band(fromChannel: 6), .ghz24)
        XCTAssertEqual(WifiLogic.band(fromChannel: 149), .ghz5)
        XCTAssertNil(WifiLogic.band(fromChannel: 0))
        XCTAssertEqual(WifiLogic.rssiToPct(-50), 100)
        XCTAssertEqual(WifiLogic.rssiToPct(-75), 50)
        XCTAssertEqual(WifiLogic.rssiToPct(-120), 0)
        XCTAssertEqual(WifiLogic.isNomap("Home_nomap"), true)
        XCTAssertEqual(WifiLogic.isNomap("Home_optout_x"), true)
        XCTAssertEqual(WifiLogic.isNomap("Home"), false)
        XCTAssertNil(WifiLogic.isNomap(nil))
    }
}
