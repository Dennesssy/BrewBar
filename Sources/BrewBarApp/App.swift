import SwiftUI
import BrewBarKit

@main
struct BrewBarApp: App {
    @StateObject private var searchState = AppSearchState()
    @StateObject private var preferencesViewModel = PreferencesViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(searchState)
        }
        
        MenuBarExtra("BrewBar", systemImage: "mug.fill", isInserted: $preferencesViewModel.preferences.showMenuBarIcon) {
            Button("Open BrewBar") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApplication.shared.windows {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            Button("Check for Updates") {
                Task {
                    try? await BrewService.shared.checkForUpdates()
                }
            }
            Button("Update All Packages") {
                Task {
                    try? await BrewService.shared.upgradeAll()
                }
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
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
        case about = "About"

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
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(Tab.sidebarCases, selection: $selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                        .badge(badgeCount(for: tab))
                }
                .navigationTitle("BrewBar")
                .toolbarBackground(.hidden, for: .windowToolbar)
                .searchable(text: $searchQuery, placement: .sidebar, prompt: "Search formulas & casks")
                .onSubmit(of: .search) {
                    guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    searchState.pendingQuery = searchQuery
                    selectedTab = .search
                }
            } detail: {
                detailView
                    .toolbarBackground(.hidden, for: .windowToolbar)
            }
            
            if let msg = brewService.activeTaskMessage {
                VStack(spacing: 6) {
                    Divider()
                    HStack {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if let percent = brewService.activeTaskProgress {
                            Text("\(Int(percent * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    
                    if let percent = brewService.activeTaskProgress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.2))
                                
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, geo.size.width * CGFloat(percent)))
                                    .animation(.linear(duration: 0.2), value: percent)
                            }
                        }
                        .frame(height: 6)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    } else {
                        ProgressView()
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut, value: brewService.activeTaskMessage != nil)
            }
        }
        .background(
            Button("Refresh") {
                Task {
                    try? await BrewService.shared.refreshInstalledPackages()
                    try? await BrewService.shared.checkForUpdates()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .hidden()
        )
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
        case .about:
            AboutView()
        }
    }
}
