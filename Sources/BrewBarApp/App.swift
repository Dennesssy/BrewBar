import SwiftUI
import BrewBarKit

@main
struct BrewBarApp: App {
    @StateObject private var searchState = AppSearchState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(searchState)
        }
    }
}

/// Shared bridge for the Discover tab's top search field to hand off a query
/// to the dedicated Search tab, mirroring the App Store's sidebar-top search.
@MainActor
final class AppSearchState: ObservableObject {
    @Published var pendingQuery: String = ""
}

struct ContentView: View {
    @State private var selectedTab: Tab = .home
    @State private var searchQuery: String = ""
    @EnvironmentObject private var searchState: AppSearchState
    @ObservedObject private var brewService = BrewService.shared
    @ObservedObject private var servicesManager = ServicesManager.shared

    enum Tab: String, CaseIterable, Identifiable {
        case discover = "Discover"
        case home = "Home"
        case installed = "Installed"
        case updates = "Updates"
        case services = "Services"
        case search = "Search"
        case settings = "Settings"

        var id: String { rawValue }

        /// Rows rendered in the sidebar list. `.search` is excluded here —
        /// like the App Store, search lives in a search field above the
        /// sidebar list (via `.searchable`), not as its own nav row.
        static var sidebarCases: [Tab] {
            allCases.filter { $0 != .search }
        }

        var systemImage: String {
            switch self {
            case .discover: return "star"
            case .home: return "house"
            case .installed: return "shippingbox"
            case .updates: return "arrow.triangle.2.circlepath"
            case .services: return "gearshape.2"
            case .search: return "magnifyingglass"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.sidebarCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.systemImage)
                    .tag(tab)
                    .badge(badgeCount(for: tab))
            }
            .navigationTitle("BrewBar")
        } detail: {
            detailView
        }
    }

    /// Real counts only — a badge of 0 renders nothing, so idle rows stay
    /// clean. Services badges only on errors (a running service isn't
    /// something that needs attention; a failed one is).
    private func badgeCount(for tab: Tab) -> Int {
        switch tab {
        case .updates:
            return brewService.availableUpdates.count
        case .services:
            return servicesManager.services.filter { $0.status == "error" }.count
        default:
            return 0
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .discover:
            DiscoverView()
        case .home:
            HomeView()
        case .installed:
            InstalledView()
        case .updates:
            UpdatesView()
        case .services:
            ServicesView()
        case .search:
            SearchView()
        case .settings:
            PreferencesView()
        }
    }
}
