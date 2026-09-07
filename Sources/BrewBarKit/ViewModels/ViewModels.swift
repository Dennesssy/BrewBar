import Foundation
import Combine

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public private(set) var featured: [FormulaItem] = []
    @Published public private(set) var recommended: [FormulaItem] = []
    @Published public private(set) var recentlyUpdated: [FormulaItem] = []
    @Published public private(set) var isLoading: Bool = false

    private let brewService = BrewService.shared

    public init() {
        loadData()
    }

    public func loadData() {
        isLoading = true

        // Featured package defaults
        featured = [
            FormulaItem(id: "python@3.11", name: "python@3.11", fullTitle: "Python 3.11", description: "Interpreted, object-oriented, high-level programming language", currentVersion: "3.11.8", type: .formula),
            FormulaItem(id: "docker", name: "docker", fullTitle: "Docker", description: "Pack, ship and run any application as a lightweight container", currentVersion: "26.0.0", type: .formula),
            FormulaItem(id: "node", name: "node", fullTitle: "Node.js", description: "Platform built on V8 JavaScript runtime", currentVersion: "21.7.1", type: .formula)
        ]

        recommended = [
            FormulaItem(id: "rust", name: "rust", fullTitle: "Rust", description: "Safe, concurrent, practical language", currentVersion: "1.77.0", type: .formula),
            FormulaItem(id: "postgresql@16", name: "postgresql@16", fullTitle: "PostgreSQL 16", description: "Object-relational database system", currentVersion: "16.2", type: .formula),
            FormulaItem(id: "redis", name: "redis", fullTitle: "Redis", description: "Persistent key-value database", currentVersion: "7.2.4", type: .formula)
        ]

        recentlyUpdated = brewService.installedPackages.prefix(5).map { $0 }
        isLoading = false
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
        case .installedDateNewest, .installedDateOldest, .sizeLargest:
            break
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
        try? await brewService.checkForUpdates()
        self.availableUpdates = brewService.availableUpdates
    }

    public func updateAll() async {
        isUpdating = true
        defer { isUpdating = false }
        try? await brewService.upgradeAll()
        await checkForUpdates()
    }

    public func updateItem(_ item: FormulaItem) async {
        try? await brewService.upgradeFormula(item.name)
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
    @Published public private(set) var reviews: [UserReview] = []
    @Published public private(set) var isLoading: Bool = false

    public init(formula: FormulaItem) {
        self.formula = formula
        loadDetails()
    }

    public func loadDetails() {
        isLoading = true
        reviews = [
            UserReview(formulaId: formula.id, authorUsername: "alex_dev", rating: 5, comment: "Works flawlessly! Highly recommended.", date: Date()),
            UserReview(formulaId: formula.id, authorUsername: "sam_k", rating: 4, comment: "Solid package, easy to configure.", date: Date())
        ]
        isLoading = false
    }

    public func install() async throws {
        try await BrewService.shared.installFormula(formula.name)
    }

    public func uninstall() async throws {
        try await BrewService.shared.uninstallFormula(formula.name)
    }
}

@MainActor
public final class PreferencesViewModel: ObservableObject {
    @Published public var preferences: UserPreferences = UserPreferences()

    public init() {
        Task {
            self.preferences = await LocalStorageManager.shared.loadPreferences()
        }
    }

    public func save() {
        Task {
            await LocalStorageManager.shared.savePreferences(preferences)
        }
    }
}
