// ContentView.swift - Main content view (wrapper for the app)

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .home
    
    enum Tab: String, CaseIterable, Identifiable {
        case home = "Home"
        case shield = "Shield"
        case speed = "Speed & Wi-Fi"
        case devices = "Devices"
        
        var id: Self { self }
        
        var icon: String {
            switch self {
            case .home: return "house"
            case .shield: return "shield.fill"
            case .speed: return "gauge"
            case .devices: return "cpu"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationTitle("Bastion")
        } detail: {
            switch selectedTab {
            case .home: HomeView()
            case .shield: ShieldView()
            case .speed: SpeedView()
            case .devices: DevicesView()
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
