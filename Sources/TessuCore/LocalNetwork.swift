import Foundation

/// macOS (15 and later) lets an app see its local network only after the user allowed "Local Network".
/// Without that, the system hides this Mac's own hardware address and returns an empty ARP table, which
/// would look exactly like "nobody else is on your network". Tessu detects this and says so.
public enum LocalNetwork {
    public static let blockedMessage =
        "macOS is hiding your local network from Tessu, so devices and this Mac's Wi-Fi address cannot be read. " +
        "Allow Tessu under System Settings > Privacy & Security > Local Network, then scan again."

    /// System Settings page for the permission.
    public static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
}
