import Foundation
import Combine

@MainActor
public final class HomeViewModel: ObservableObject {
    /// Real 30-day install-count leaders among formulas (formulae.brew.sh
    /// analytics), not hand-picked.
    @Published public private(set) var featured: [FormulaItem] = []
    /// Real 30-day install-count leaders among casks.
    @Published public private(set) var recommended: [FormulaItem] = []
    @Published public private(set) var recentlyUpdated: [FormulaItem] = []
    @Published public private(set) var isLoading: Bool = false

    private let brewService = BrewService.shared
    private let catalog = HomebrewCatalogService.shared

    public init() {}

    public func loadData() async {
        isLoading = true
        defer { isLoading = false }

        await catalog.loadIfNeeded()
        featured = catalog.topFormulas(limit: 6)
        recommended = catalog.topCasks(limit: 6)
        recentlyUpdated = brewService.installedPackages.prefix(6).map { $0 }
    }
}

@MainActor
public final class InstalledViewModel: ObservableObject {
    @Published public var filterState = FilterState()
    @Published public var sortOrder: SortOrderOption = .nameAscending

    private let brewService = BrewService.shared

    public init() {}

    public var filteredFormulas: [FormulaItem] {
        var items = brewService.installedPackages

        if let type = filterState.selectedType {
            items = items.filter { $0.type == type }
        }

        if filterState.onlyUpdates {
            items = items.filter { $0.updateAvailable }
        }

        if !filterState.searchQuery.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(filterState.searchQuery) ||
                $0.description.localizedCaseInsensitiveContains(filterState.searchQuery)
            }
        }

        switch sortOrder {
        case .nameAscending:
            items.sort { $0.name.lowercased() < $1.name.lowercased() }
        case .nameDescending:
            items.sort { $0.name.lowercased() > $1.name.lowercased() }
        case .installedDateNewest:
            items.sort { ($0.installedDate ?? .distantPast) > ($1.installedDate ?? .distantPast) }
        case .installedDateOldest:
            items.sort { ($0.installedDate ?? .distantPast) < ($1.installedDate ?? .distantPast) }
        case .sizeLargest:
            items.sort { ($0.sizeInBytes ?? 0) > ($1.sizeInBytes ?? 0) }
        }

        return items
    }

    public func refresh() async {
        try? await brewService.refreshInstalledPackages()
    }
}

@MainActor
public final class UpdatesViewModel: ObservableObject {
    @Published public private(set) var availableUpdates: [FormulaItem] = []
    @Published public private(set) var isUpdating: Bool = false
    @Published public private(set) var updateProgress: Double = 0.0

    private let brewService = BrewService.shared

    public init() {}

    public func checkForUpdates() async {
        do {
            try await brewService.checkForUpdates()
            self.availableUpdates = brewService.availableUpdates
        } catch {
            self.availableUpdates = []
        }
    }

    public func updateAll() async {
        isUpdating = true
        defer { isUpdating = false }
        try? await brewService.upgradeAll()
        await checkForUpdates()
    }

    public func updateItem(_ item: FormulaItem) async {
        try? await brewService.upgradeFormula(item.id, type: item.type)
        await checkForUpdates()
    }
}

@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public var query: String = ""
    @Published public var filterState = FilterState()
    @Published public private(set) var results: [FormulaItem] = []
    @Published public private(set) var isSearching: Bool = false

    private let searchService = SearchService.shared

    public init() {}

    public func performSearch() async {
        isSearching = true
        defer { isSearching = false }
        results = await searchService.search(query, filters: filterState)
    }
}

@MainActor
public final class FormulaDetailViewModel: ObservableObject {
    @Published public var formula: FormulaItem
    @Published public var githubStars: Int?
    @Published public var githubReadme: String?
    @Published public var isFetchingDetails = false

    public init(formula: FormulaItem) {
        self.formula = formula
    }

    public func fetchRichDetailsIfNeeded() {
        guard githubStars == nil && !isFetchingDetails else { return }
        
        // Extract owner/repo from homepage or repository if it's GitHub
        var repoPath: String?
        if let homepage = formula.homepage, homepage.contains("github.com") {
            let parts = URL(string: homepage)?.pathComponents.filter { $0 != "/" } ?? []
            if parts.count >= 2 {
                repoPath = "\(parts[0])/\(parts[1])"
            }
        }
        
        guard let targetRepo = repoPath else { return }
        isFetchingDetails = true
        
        Task {
            let token = try? KeychainManager.shared.retrieveToken(service: "com.dennesssy.brewbar.github")
            
            func makeRequest(for urlStr: String) -> URLRequest? {
                guard let url = URL(string: urlStr) else { return nil }
                var req = URLRequest(url: url)
                if let token = token, !token.isEmpty {
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                return req
            }

            // Fetch Stars
            if let req = makeRequest(for: "https://api.github.com/repos/\(targetRepo)"),
               let (data, _) = try? await URLSession.shared.data(for: req),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let stars = json["stargazers_count"] as? Int {
                DispatchQueue.main.async { self.githubStars = stars }
            }
            
            // Fetch Readme
            if let req = makeRequest(for: "https://api.github.com/repos/\(targetRepo)/readme"),
               let (data, _) = try? await URLSession.shared.data(for: req),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? String {
                let cleanedContent = content.replacingOccurrences(of: "\n", with: "")
                if let decodedData = Data(base64Encoded: cleanedContent),
                   let readmeString = String(data: decodedData, encoding: .utf8) {
                    DispatchQueue.main.async { self.githubReadme = readmeString }
                }
            }
            
            DispatchQueue.main.async { self.isFetchingDetails = false }
        }
    }

    /// Installs the formula, or upgrades it if it's already installed with
    /// an update pending — matches the "Install"/"Update" button it backs.
    public func install() async throws {
        if formula.updateAvailable {
            try await BrewService.shared.upgradeFormula(formula.id, type: formula.type)
        } else {
            try await BrewService.shared.installFormula(formula.id, type: formula.type)
        }
    }

    public func uninstall() async throws {
        try await BrewService.shared.uninstallFormula(formula.id, type: formula.type)
    }
}

@MainActor
public final class PreferencesViewModel: ObservableObject {
    @Published public var preferences: UserPreferences = UserPreferences()

    @Published public var githubToken: String = ""

    public init() {
        Task {
            self.preferences = await LocalStorageManager.shared.loadPreferences()
            if let token = try? KeychainManager.shared.retrieveToken(service: "com.dennesssy.brewbar.github") {
                DispatchQueue.main.async { self.githubToken = token }
            }
        }
    }

    public func save() {
        Task {
            await LocalStorageManager.shared.savePreferences(preferences)
        }
    }
    
    public func saveToken(_ token: String) {
        if token.isEmpty {
            try? KeychainManager.shared.deleteToken(service: "com.dennesssy.brewbar.github")
        } else {
            try? KeychainManager.shared.saveToken(token, service: "com.dennesssy.brewbar.github")
        }
    }
}

public struct PackageCategory: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let systemImage: String
    public let items: [FormulaItem]

    public init(id: String, name: String, systemImage: String, items: [FormulaItem]) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.items = items
    }
}

@MainActor
public final class DiscoverViewModel: ObservableObject {
    @Published public private(set) var categories: [PackageCategory] = []
    /// Real 30-day install-count leaders (formulae.brew.sh analytics) — not
    /// an editorial pick, since BrewBar has no curation team to back that claim.
    @Published public private(set) var trending: [FormulaItem] = []
    /// Resolved from `brew update`'s real "New Formulae"/"New Casks" output.
    @Published public private(set) var newThisWeek: [FormulaItem] = []
    @Published public private(set) var totalAvailableCount: Int = 0

    private let catalog = HomebrewCatalogService.shared
    private let brewService = BrewService.shared

    public init() {}

    public func load() async {
        await catalog.loadIfNeeded()
        buildContent()
    }

    private func buildContent() {
        trending = catalog.topFormulas(limit: 9) + catalog.topCasks(limit: 6)
        totalAvailableCount = catalog.totalFormulaCount + catalog.totalCaskCount

        newThisWeek = brewService.newFormulaNames.compactMap(catalog.formula)
            + brewService.newCaskNames.compactMap(catalog.cask)

        categories = [
            PackageCategory(
                id: "dev-tools", name: "Developer Tools", systemImage: "hammer",
                items: catalog.formulasMatching(
                    keywords: ["revision control", "version control", "command line interface",
                               "compiler", "build system", "programming language", "debugger", "static analysis"],
                    limit: 15
                )
            ),
            PackageCategory(
                id: "databases", name: "Databases", systemImage: "cylinder.split.1x2",
                items: catalog.formulasMatching(
                    keywords: ["database", "key-value", "relational database", "nosql", "in-memory data structure"],
                    limit: 15
                )
            ),
            PackageCategory(
                id: "apps", name: "Apps & Browsers", systemImage: "app.badge",
                items: catalog.topCasks(limit: 15)
            ),
            PackageCategory(
                id: "productivity", name: "Productivity", systemImage: "checklist",
                items: catalog.casksMatching(
                    keywords: ["note-taking", "task manager", "productivity", "launcher", "to-do", "notes app", "calendar"],
                    limit: 15
                )
            )
        ]
    }
}
