import SwiftUI
import BrewBarKit

@main
struct BrewBarApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: Tab = .home

    enum Tab: String, CaseIterable, Identifiable {
        case home = "Home"
        case installed = "Installed"
        case updates = "Updates"
        case search = "Search"
        case settings = "Settings"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .home: return "house"
            case .installed: return "shippingbox"
            case .updates: return "arrow.triangle.2.circlepath"
            case .search: return "magnifyingglass"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .navigationTitle("BrewBar")
        } detail: {
            switch selectedTab {
            case .home:
                HomeView()
            case .installed:
                InstalledView()
            case .updates:
                UpdatesView()
            case .search:
                SearchView()
            case .settings:
                PreferencesView()
            }
        }
    }
}
