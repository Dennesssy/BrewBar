import Foundation

@MainActor
public final class PackageService: ObservableObject {
    public static let shared = PackageService()

    private let brewService = BrewService.shared

    public init() {}

    public func getInstalledPackages() -> [FormulaItem] {
        return brewService.installedPackages
    }

    public func installPackage(_ item: FormulaItem) async throws {
        try await brewService.installFormula(item.name)
    }

    public func upgradePackage(_ item: FormulaItem) async throws {
        try await brewService.upgradeFormula(item.name)
    }

    public func removePackage(_ item: FormulaItem) async throws {
        try await brewService.uninstallFormula(item.name)
    }
}

@MainActor
public final class SearchService: ObservableObject {
    public static let shared = SearchService()

    @Published public private(set) var searchResults: [FormulaItem] = []
    @Published public private(set) var recentSearches: [String] = []
    @Published public private(set) var isSearching: Bool = false

    private let githubClient = GitHubAPIClient.shared

    public init() {}

    public func search(_ query: String, filters: FilterState = .defaultFilters) async -> [FormulaItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.searchResults = []
            return []
        }

        self.isSearching = true
        defer { self.isSearching = false }

        var results: [FormulaItem] = []

        // 1. Local installed match
        let local = BrewService.shared.installedPackages.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query)
        }
        results.append(contentsOf: local)

        // 2. Remote GitHub Search
        do {
            let remote = try await githubClient.searchFormulas(query: query)
            let existingIds = Set(results.map { $0.id })
            for item in remote {
                if !existingIds.contains(item.id) {
                    results.append(item)
                }
            }
        } catch {
            Logger.shared.error("Remote search error: \(error.localizedDescription)")
        }

        // Apply type filter if selected
        if let type = filters.selectedType {
            results = results.filter { $0.type == type }
        }

        self.searchResults = results
        addToRecentSearches(query)
        return results
    }

    private func addToRecentSearches(_ query: String) {
        recentSearches.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        recentSearches.insert(query, at: 0)
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }
    }

    public func clearRecentSearches() {
        recentSearches.removeAll()
    }
}

@MainActor
public final class UpdateCheckService: ObservableObject {
    public static let shared = UpdateCheckService()

    @Published public private(set) var lastCheckTime: Date?
    private var timer: Timer?

    public init() {}

    public func startPeriodicChecks(interval: TimeInterval = 3600) {
        stopPeriodicChecks()
        Task {
            await performCheck()
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performCheck()
            }
        }
    }

    public func stopPeriodicChecks() {
        timer?.invalidate()
        timer = nil
    }

    public func performCheck() async {
        do {
            try await BrewService.shared.checkForUpdates()
            self.lastCheckTime = Date()
        } catch {
            Logger.shared.error("Update check failed: \(error.localizedDescription)")
        }
    }
}

@MainActor
public final class NotificationManager: ObservableObject {
    public static let shared = NotificationManager()

    public init() {}

    public func notifyInstallationComplete(packageName: String) {
        Logger.shared.info("Notification: Installation completed for \(packageName)")
    }

    public func notifyInstallationFailed(packageName: String, error: String) {
        Logger.shared.error("Notification: Installation failed for \(packageName): \(error)")
    }
}

@MainActor
public final class GitHubAuthManager: ObservableObject {
    public static let shared = GitHubAuthManager()

    @Published public private(set) var currentUser: GitHubUser?
    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var isAuthenticating: Bool = false
    @Published public var authError: String?

    public init() {
        loadStoredToken()
    }

    public func logout() {
        currentUser = nil
        isAuthenticated = false
        try? KeychainManager.shared.deleteToken(service: "github_oauth_token")
    }

    private func loadStoredToken() {
        Task {
            if let token = try? KeychainManager.shared.retrieveToken(service: "github_oauth_token"), !token.isEmpty {
                self.isAuthenticated = true
            }
        }
    }
}

@MainActor
public final class AnalyticsService: ObservableObject {
    public static let shared = AnalyticsService()

    public init() {}

    public func logEvent(name: String, parameters: [String: String] = [:]) {
        Task {
            await AnalyticsReporter.shared.trackEvent(name: name, parameters: parameters)
        }
    }
}
