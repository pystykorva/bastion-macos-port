import XCTest
@testable import TessuCore

final class NetUtilTests: XCTestCase {
    func testNormalizeMac() {
        XCTAssertEqual(NetUtil.normalizeMac("AA-BB-CC-DD-EE-FF"), "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(NetUtil.normalizeMac("a:b:c:d:e:f"), "0a:0b:0c:0d:0e:0f", "macOS arp prints unpadded octets")
        XCTAssertEqual(NetUtil.normalizeMac("88:70:15:0:44:10"), "88:70:15:00:44:10")
        XCTAssertEqual(NetUtil.normalizeMac("aabbccddeeff"), "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(NetUtil.normalizeMac("aabb.ccdd.eeff"), "aa:bb:cc:dd:ee:ff")
        XCTAssertNil(NetUtil.normalizeMac("00:00:00:00:00:00"))
        XCTAssertNil(NetUtil.normalizeMac("(incomplete)"))
        XCTAssertNil(NetUtil.normalizeMac("aa:bb:cc"))
        XCTAssertNil(NetUtil.normalizeMac(nil))
    }

    func testRandomizedAndMulticastMac() {
        XCTAssertEqual(NetUtil.isRandomizedMac("da:a1:19:00:00:01"), true, "locally administered bit set")
        XCTAssertEqual(NetUtil.isRandomizedMac("24:4b:fe:bd:f6:80"), false)
        XCTAssertEqual(NetUtil.isRandomizedMac("01:00:5e:00:00:fb"), false, "multicast is not a device address")
        XCTAssertNil(NetUtil.isRandomizedMac("garbage"))
        XCTAssertTrue(NetUtil.isMulticastMac("ff:ff:ff:ff:ff:ff"))
        XCTAssertTrue(NetUtil.isMulticastMac("01:00:5e:00:00:fb"))
        XCTAssertFalse(NetUtil.isMulticastMac("24:4b:fe:bd:f6:80"))
    }

    func testRedactedMacIsNotJudgedAsRandomized() {
        XCTAssertTrue(NetUtil.isRedactedMac("02:00:00:00:00:00"))
        XCTAssertFalse(NetUtil.isRedactedMac("ce:b8:74:61:6f:89"))
    }

    func testIPv4Helpers() {
        XCTAssertTrue(NetUtil.isIPv4("192.168.1.1"))
        XCTAssertFalse(NetUtil.isIPv4("192.168.1.256"))
        XCTAssertFalse(NetUtil.isIPv4("1.2.3"))
        XCTAssertFalse(NetUtil.isIPv4("a.b.c.d"))
        XCTAssertFalse(NetUtil.isIPv4(nil))
        XCTAssertEqual(NetUtil.ipToInt("192.168.1.1"), 3232235777)
        XCTAssertEqual(NetUtil.intToIp(3232235777), "192.168.1.1")
        XCTAssertEqual(NetUtil.prefixToMask(24), 0xFFFFFF00)
        XCTAssertEqual(NetUtil.prefixToMask(0), 0)
        XCTAssertEqual(NetUtil.maskToPrefix("255.255.255.0"), 24)
        XCTAssertTrue(NetUtil.sameSubnet("192.168.1.1", "192.168.1.200", prefix: 24))
        XCTAssertFalse(NetUtil.sameSubnet("192.168.1.1", "192.168.2.1", prefix: 24))
    }

    func testPrivateLoopbackMulticast() {
        for ip in ["10.0.0.1", "172.16.0.1", "172.31.255.255", "192.168.0.1", "169.254.1.1"] { XCTAssertTrue(NetUtil.isPrivateIPv4(ip), ip) }
        for ip in ["8.8.8.8", "172.32.0.1", "172.15.0.1", "100.64.0.1", "192.169.0.1"] { XCTAssertFalse(NetUtil.isPrivateIPv4(ip), ip) }
        XCTAssertTrue(NetUtil.isLoopback("127.0.0.1"))
        XCTAssertTrue(NetUtil.isLoopback("::1"))
        XCTAssertTrue(NetUtil.isLoopback("[::1]"))
        XCTAssertFalse(NetUtil.isLoopback("192.168.1.1"))
        XCTAssertTrue(NetUtil.isMulticastIPv4("224.0.0.251"))
        XCTAssertFalse(NetUtil.isMulticastIPv4("192.168.1.1"))
    }

    func testVendorLookup() {
        XCTAssertEqual(Vendors.vendor(for: "00:0a:27:11:22:33"), "Apple")
        XCTAssertNil(Vendors.vendor(for: "da:a1:19:00:00:01"), "randomized MACs have no vendor")
        XCTAssertNil(Vendors.vendor(for: "fe:ed:fa:ce:00:01"))
        XCTAssertEqual(Vendors.tableSize, 664, "table must match the original vendors.js")
    }
}
