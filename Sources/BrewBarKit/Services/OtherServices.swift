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
        try await brewService.installFormula(item.id, type: item.type)
        await SpotlightIndexer.shared.indexPackages([item])
    }

    public func upgradePackage(_ item: FormulaItem) async throws {
        try await brewService.upgradeFormula(item.id, type: item.type)
        await SpotlightIndexer.shared.indexPackages([item])
    }

    public func removePackage(_ item: FormulaItem) async throws {
        try await brewService.uninstallFormula(item.id, type: item.type)
        await SpotlightIndexer.shared.removePackageFromIndex(id: item.id, type: item.type)
    }
}

/// Wraps `brew services` — background daemons (postgres, redis, nginx, etc.)
/// managed via launchctl. Distinct from `PackageService`: services are a
/// runtime state (started/stopped) layered on top of an installed formula,
/// not the install/uninstall lifecycle itself.
@MainActor
public final class ServicesManager: ObservableObject {
    public static let shared = ServicesManager()

    @Published public private(set) var services: [BrewServiceStatus] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: BrewBarError?
    @Published public private(set) var pendingActions: Set<String> = []

    private let processManager = ProcessManager()
    private let outputParser = OutputParser()
    private let errorHandler = ErrorHandler()

    public init() {}

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).servicesList()

        do {
            let output = try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments())
            self.services = try outputParser.parseServices(output)
            self.lastError = nil
        } catch {
            self.lastError = errorHandler.handle(error)
        }
    }

    public func start(_ name: String) async {
        await performAction(.start, name: name)
    }

    public func stop(_ name: String) async {
        await performAction(.stop, name: name)
    }

    public func restart(_ name: String) async {
        await performAction(.restart, name: name)
    }

    private func performAction(_ action: BrewCommandBuilder.ServiceAction, name: String) async {
        pendingActions.insert(name)
        defer { pendingActions.remove(name) }

        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).servicesAction(action, formula: name)

        do {
            _ = try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments(), timeout: 60)
            self.lastError = nil
        } catch {
            self.lastError = errorHandler.handle(error)
        }
        await refresh()
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
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            self.searchResults = []
            return []
        }

        self.isSearching = true
        defer { self.isSearching = false }

        var candidates: [FormulaItem] = []

        // 1. Local installed packages candidates
        candidates.append(contentsOf: BrewService.shared.installedPackages)

        // 2. Remote GitHub Search candidates
        do {
            let remote = try await githubClient.searchFormulas(query: cleanQuery)
            let existingIds = Set(candidates.map { $0.id })
            for item in remote {
                if !existingIds.contains(item.id) {
                    candidates.append(item)
                }
            }
        } catch {
            Logger.shared.error("Remote search error: \(error.localizedDescription)")
        }

        // Apply type filter if selected
        if let type = filters.selectedType {
            candidates = candidates.filter { $0.type == type }
        }

        // Apply Semantic Lookup and Relevance Ranking
        let rankedResults = SemanticSearchEngine.searchAndRank(items: candidates, query: cleanQuery)

        self.searchResults = rankedResults
        addToRecentSearches(cleanQuery)
        return rankedResults
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
