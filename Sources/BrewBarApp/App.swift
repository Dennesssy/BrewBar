// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

import Combine
import CoreSpotlight

/// The menu bar item's visibility, kept apart from `PreferencesViewModel`. If the `App` observed
/// that model directly, every published preference change would rebuild the whole scene list.
@MainActor
final class MenuBarVisibility: ObservableObject {
    @Published private(set) var isInserted = true
    private var subscription: AnyCancellable?

    init() {
        subscription = PreferencesViewModel.shared.$preferences
            .map(\.showMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] value in
                guard let self, self.isInserted != value else { return }
                self.isInserted = value
            }
    }

    func set(_ value: Bool) {
        guard isInserted != value else { return }
        isInserted = value
        let preferences = PreferencesViewModel.shared
        preferences.preferences.showMenuBarIcon = value
        preferences.save()
    }
}

@main
struct BrewBarApp: App {
    @StateObject private var searchState = AppSearchState()
    @StateObject private var menuBarVisibility = MenuBarVisibility()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(searchState)
                .modelContainer(HistoryStore.shared.container)
                .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                    if let id = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        let parts = id.components(separatedBy: ":")
                        if parts.count == 3 {
                            searchState.pendingQuery = parts[2]
                        }
                    }
                }
        }
        .defaultSize(width: 1180, height: 800)
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings {
            PreferencesView()
                .frame(width: 620, height: 640)
        }
        
        MenuBarExtra("BrewBar", systemImage: "mug.fill", isInserted: Binding(get: { menuBarVisibility.isInserted }, set: { menuBarVisibility.set($0) })) {
            Button("Open BrewBar") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApplication.shared.windows {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            Button("Check for Updates") {
                Task {
                    do {
                        try await BrewService.shared.checkForUpdates()
                    } catch {
                        showUpgradeAlert(
                            message: "Could not check for updates",
                            info: error.localizedDescription,
                            style: .warning,
                            buttons: ["OK"]
                        )
                    }
                }
            }
            Button("Update All Packages") {
                Task {
                    await confirmAndUpgradeAll()
                }
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)

        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About BrewBar") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
    }
}

/// Dry-runs `brew upgrade` and asks before upgrading everything from the menu bar.
@MainActor
private func confirmAndUpgradeAll() async {
    let preview: String
    do {
        preview = try await BrewService.shared.dryRunUpgradeAll()
    } catch {
        showUpgradeAlert(
            message: "Could not check for upgrades",
            info: error.localizedDescription,
            style: .warning,
            buttons: ["OK"]
        )
        return
    }

    let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        showUpgradeAlert(
            message: "All packages are up to date",
            info: "There is nothing to upgrade.",
            style: .informational,
            buttons: ["OK"]
        )
        return
    }

    let maxLines = 40
    var lines = trimmed.components(separatedBy: "\n")
    if lines.count > maxLines {
        lines = Array(lines.prefix(maxLines)) + ["…"]
    }

    let choice = showUpgradeAlert(
        message: "Upgrade all packages?",
        info: lines.joined(separator: "\n"),
        style: .warning,
        buttons: ["Upgrade", "Cancel"]
    )
    guard choice == .alertFirstButtonReturn else { return }
    do {
        try await BrewService.shared.upgradeAll()
    } catch {
        showUpgradeAlert(
            message: "Upgrade failed",
            info: error.localizedDescription,
            style: .warning,
            buttons: ["OK"]
        )
    }
}

@MainActor
@discardableResult
private func showUpgradeAlert(
    message: String,
    info: String,
    style: NSAlert.Style,
    buttons: [String]
) -> NSApplication.ModalResponse {
    NSApp.activate()
    let alert = NSAlert()
    alert.alertStyle = style
    alert.messageText = message
    alert.informativeText = info
    for title in buttons {
        alert.addButton(withTitle: title)
    }
    return alert.runModal()
}

/// Shared bridge for the Discover tab's top search field to hand off a query
/// to the dedicated Search tab, mirroring the App Store's sidebar-top search.
@MainActor
final class AppSearchState: ObservableObject {
    @Published var pendingQuery: String = ""
}

/// Sidebar grouping, mirroring the App Store's Browse / Library sections.
struct SidebarGroup: Identifiable {
    let title: String
    let tabs: [ContentView.Tab]

    var id: String { title }
}

struct ContentView: View {
    @State private var selectedTab: Tab = .discover
    @State private var searchQuery: String = ""
    @EnvironmentObject private var searchState: AppSearchState
    @ObservedObject private var brewService = BrewService.shared
    @ObservedObject private var servicesManager = ServicesManager.shared
    @ObservedObject private var environment = HomebrewEnvironment.shared

    enum Tab: String, CaseIterable, Identifiable {
        case discover = "Discover"
        case home = "Home"
        case installed = "Installed"
        case updates = "Updates"
        case services = "Services"
        case storage = "Storage"
        case history = "History"
        case doctor = "Doctor"
        case security = "Security"
        case accounts = "Accounts"
        case config = "Configuration"
        case agentTools = "Agent Tools"
        case search = "Search"
        case settings = "Settings"
        // case about = "About"

        var id: String { rawValue }

        /// Rows rendered in the sidebar list. Search lives in the sidebar's
        /// search field (`.searchable`) and Settings lives in the standard
        /// Settings scene (⌘,), so neither is a nav row.
        static var sidebarCases: [Tab] {
            allCases.filter { $0 != .search && $0 != .settings }
        }

        static var sidebarGroups: [SidebarGroup] {
            [
                SidebarGroup(title: "Browse", tabs: [.discover, .home]),
                SidebarGroup(title: "Library", tabs: [.installed, .updates]),
                SidebarGroup(title: "Maintenance", tabs: [.services, .storage, .history, .doctor, .security]),
                SidebarGroup(title: "Advanced", tabs: [.accounts, .config, .agentTools]),
            ]
        }

        var systemImage: String {
            switch self {
            case .discover: return "star"
            case .home: return "house"
            case .installed: return "shippingbox"
            case .updates: return "arrow.triangle.2.circlepath"
            case .services: return "gearshape.2"
            case .storage: return "externaldrive"
            case .history: return "clock"
            case .doctor: return "stethoscope"
            case .security: return "lock.shield"
            case .accounts: return "person.2"
            case .config: return "slider.horizontal.3"
            case .agentTools: return "terminal"
            case .search: return "magnifyingglass"
            case .settings: return "gearshape"
            }
        }
        
        var keyboardShortcutKey: KeyEquivalent? {
            let cases = Tab.sidebarCases
            if let idx = cases.firstIndex(of: self), idx < 9 {
                let char = Character(String(idx + 1))
                return KeyEquivalent(char)
            }
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $selectedTab) {
                    ForEach(Tab.sidebarGroups) { group in
                        Section(group.title) {
                            ForEach(group.tabs) { tab in
                                Label(tab.rawValue, systemImage: tab.systemImage)
                                    .tag(tab)
                                    .badge(badgeCount(for: tab))
                            }
                        }
                    }
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
                TaskConsoleView(
                    message: msg,
                    progress: brewService.activeTaskProgress,
                    command: brewService.activeTaskCommand,
                    output: brewService.activeTaskConsoleOutput
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut, value: brewService.activeTaskMessage != nil)
            }
        }
        .background(
            ZStack {
                Button("Refresh") {
                    Task {
                        try? await BrewService.shared.refreshInstalledPackages()
                        try? await BrewService.shared.checkForUpdates()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                
                ForEach(Tab.sidebarCases, id: \.self) { tab in
                    if let key = tab.keyboardShortcutKey {
                        Button(tab.rawValue) {
                            selectedTab = tab
                        }
                        .keyboardShortcut(key, modifiers: .command)
                    }
                }
            }
            .hidden()
        )
        .task {
            await environment.refresh()
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { brewService.presentedError != nil },
                set: { isPresented in
                    if !isPresented { brewService.presentedError = nil }
                }
            ),
            presenting: brewService.presentedError
        ) { _ in
            Button("OK", role: .cancel) {
                brewService.presentedError = nil
            }
        } message: { error in
            Text(
                [error.errorDescription, error.recoverySuggestion]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
            )
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
        if selectedTab == .settings {
            PreferencesView()
        } else if isCheckingHomebrew {
            ProgressView("Looking for Homebrew…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !environment.isAvailable {
            HomebrewSetupView()
        } else {
            tabContent
        }
    }

    private var isCheckingHomebrew: Bool {
        if case .checking = environment.status { return true }
        return false
    }

    @ViewBuilder
    private var tabContent: some View {
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
        case .storage:
            StorageView()
        case .history:
            HistoryView()
        case .doctor:
            DoctorView()
        case .security:
            SecurityView()
        case .accounts:
            AccountsView()
        case .config:
            ConfigView()
        case .agentTools:
            AgentToolsView()
        case .search:
            SearchView()
        case .settings:
            PreferencesView()
        }
    }
}
