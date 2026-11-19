import CoreLocation
import Foundation

/// macOS hides Wi-Fi network names (SSID, BSSID) from apps without Location access. An app only appears
/// in System Settings > Location Services after it has asked once, so Tessu asks once at launch,
/// explaining that it reads only the Wi-Fi name and channel. The location itself is never read or stored.
@MainActor
final class LocationAuthorizer: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var allowed: Bool { status == .authorizedAlways }

    func requestIfNeeded() {
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in self.status = s }
    }
}
