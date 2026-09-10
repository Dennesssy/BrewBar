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
            }
            .navigationTitle("BrewBar")
            .searchable(text: $searchQuery, placement: .sidebar, prompt: "Search formulas & casks")
            .onSubmit(of: .search) {
                guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                searchState.pendingQuery = searchQuery
                selectedTab = .search
            }
        } detail: {
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
}
