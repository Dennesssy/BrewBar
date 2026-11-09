// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation
import AppKit

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
            let output = try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments(), extraEnvironment: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
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

    public func showLog(_ name: String) async {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).servicesInfo(name)

        do {
            let output = try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments(), extraEnvironment: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
            if let data = output.data(using: .utf8),
               let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = jsonArray.first,
               let logPath = first["log_path"] as? String,
               !logPath.isEmpty {
                NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
            } else {
                self.lastError = BrewBarError.parseError("No log path found for service \(name).")
            }
        } catch {
            self.lastError = errorHandler.handle(error)
        }
    }

    private func performAction(_ action: BrewCommandBuilder.ServiceAction, name: String) async {
        pendingActions.insert(name)
        defer { pendingActions.remove(name) }

        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).servicesAction(action, formula: name)
        let commandArgs = builder.buildArguments()

        do {
            let output = try await BrewService.shared.runTask(
                executablePath: builder.executablePath,
                arguments: commandArgs,
                timeout: 60,
                defaultMessage: "\(action.rawValue.capitalized)ing service \(name)..."
            )
            self.lastError = nil
            HistoryStore.shared.log(packageName: name, packageType: "service", action: "service \(action.rawValue)", details: output)
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

        // Search the full Homebrew catalog locally, so results are complete
        // and instant instead of depending on GitHub's topic search.
        let catalog = HomebrewCatalogService.shared
        await catalog.loadIfNeeded()
        var results = catalog.search(cleanQuery, limit: 80)

        // Packages from taps or deprecated formulae may not be in the public
        // catalog; include installed matches that the catalog missed.
        let knownIds = Set(results.map(\.id))
        let installedMatches = BrewService.shared.installedPackages.filter { item in
            guard !knownIds.contains(item.id) else { return false }
            return item.name.localizedCaseInsensitiveContains(cleanQuery)
                || item.id.localizedCaseInsensitiveContains(cleanQuery)
                || item.description.localizedCaseInsensitiveContains(cleanQuery)
        }
        if !installedMatches.isEmpty {
            results.insert(contentsOf: installedMatches, at: 0)
        }

        if let type = filters.selectedType {
            results = results.filter { $0.type == type }
        }

        // Only reach for GitHub when the catalog has nothing — it is a
        // suggestion fallback, not the primary index.
        if results.isEmpty, cleanQuery.count >= 3 {
            do {
                results = try await githubClient.searchFormulas(query: cleanQuery)
            } catch {
                Logger.shared.error("Remote search error: \(error.localizedDescription)")
            }
        }

        self.searchResults = results
        addToRecentSearches(cleanQuery)
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

