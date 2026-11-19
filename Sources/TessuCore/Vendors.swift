import Foundation

/// Vendor lookup from the embedded OUI table. A miss returns nil ("not in Tessu's list"), never a guess.
/// Randomized (locally administered) MACs have no vendor at all.
public enum Vendors {
    public static func vendor(for mac: String?) -> String? {
        guard let m = NetUtil.normalizeMac(mac) else { return nil }
        if NetUtil.isRandomizedMac(m) == true { return nil }
        let prefix = m.replacingOccurrences(of: ":", with: "").prefix(6).uppercased()
        return VendorTable.entries[prefix]
    }

    public static var tableSize: Int { VendorTable.entries.count }
}
