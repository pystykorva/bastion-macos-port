import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case home, shield, speed, devices, agents, settings, support, credits
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .shield: return "Shield"
        case .speed: return "Speed & Wi-Fi"
        case .devices: return "Devices"
        case .agents: return "Agents"
        case .settings: return "Settings"
        case .support: return "Support"
        case .credits: return "Credits"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .shield: return "checkmark.shield"
        case .speed: return "wifi"
        case .devices: return "desktopcomputer"
        case .agents: return "sparkles"
        case .settings: return "gearshape"
        case .support: return "heart"
        case .credits: return "info.circle"
        }
    }
}
