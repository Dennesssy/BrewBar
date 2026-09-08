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
        try? await brewService.upgradeFormula(item.id)
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

    public init(formula: FormulaItem) {
        self.formula = formula
    }

    public func install() async throws {
        try await BrewService.shared.installFormula(formula.id)
    }

    public func uninstall() async throws {
        try await BrewService.shared.uninstallFormula(formula.id)
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
    @Published public private(set) var editorsPicks: [FormulaItem] = []

    public init() {
        loadCuratedContent()
    }

    public func loadCuratedContent() {
        categories = [
            PackageCategory(id: "dev-tools", name: "Developer Tools", systemImage: "hammer", items: [
                FormulaItem(id: "git", name: "git", fullTitle: "Git", description: "Distributed version control system", currentVersion: "2.44.0", type: .formula, homepage: "https://git-scm.com", license: "GPL-2.0-only"),
                FormulaItem(id: "gh", name: "gh", fullTitle: "GitHub CLI", description: "GitHub's official command line tool", currentVersion: "2.45.0", type: .formula, homepage: "https://cli.github.com", license: "MIT"),
                FormulaItem(id: "docker", name: "docker", fullTitle: "Docker", description: "Pack, ship and run any application as a lightweight container", currentVersion: "26.0.0", type: .formula, homepage: "https://www.docker.com", license: "Apache-2.0")
            ]),
            PackageCategory(id: "databases", name: "Databases", systemImage: "cylinder.split.1x2", items: [
                FormulaItem(id: "postgresql@16", name: "postgresql@16", fullTitle: "PostgreSQL 16", description: "Object-relational database system", currentVersion: "16.2", type: .formula, homepage: "https://www.postgresql.org", license: "PostgreSQL"),
                FormulaItem(id: "redis", name: "redis", fullTitle: "Redis", description: "Persistent key-value database", currentVersion: "7.2.4", type: .formula, homepage: "https://redis.io", license: "RSALv2"),
                FormulaItem(id: "sqlite", name: "sqlite", fullTitle: "SQLite", description: "Command-line interface for SQLite", currentVersion: "3.45.0", type: .formula, homepage: "https://www.sqlite.org", license: "blessing")
            ]),
            PackageCategory(id: "apps", name: "Apps & Browsers", systemImage: "app.badge", items: [
                FormulaItem(id: "google-chrome", name: "Google Chrome", fullTitle: "Google Chrome", description: "Web browser", currentVersion: "123.0", type: .cask, homepage: "https://www.google.com/chrome"),
                FormulaItem(id: "visual-studio-code", name: "Visual Studio Code", fullTitle: "Visual Studio Code", description: "Code editor", currentVersion: "1.88.0", type: .cask, homepage: "https://code.visualstudio.com"),
                FormulaItem(id: "rectangle", name: "Rectangle", fullTitle: "Rectangle", description: "Move and resize windows using keyboard shortcuts or snap areas", currentVersion: "0.79", type: .cask, homepage: "https://rectangleapp.com", license: "MIT")
            ]),
            PackageCategory(id: "productivity", name: "Productivity", systemImage: "checklist", items: [
                FormulaItem(id: "raycast", name: "Raycast", fullTitle: "Raycast", description: "Blazingly fast, totally extendable launcher", currentVersion: "1.75.0", type: .cask, homepage: "https://www.raycast.com"),
                FormulaItem(id: "obsidian", name: "Obsidian", fullTitle: "Obsidian", description: "Knowledge base that works on top of local Markdown files", currentVersion: "1.5.12", type: .cask, homepage: "https://obsidian.md"),
                FormulaItem(id: "rust", name: "rust", fullTitle: "Rust", description: "Safe, concurrent, practical language", currentVersion: "1.77.0", type: .formula, homepage: "https://www.rust-lang.org", license: "Apache-2.0")
            ])
        ]

        editorsPicks = [
            FormulaItem(id: "node", name: "node", fullTitle: "Node.js", description: "Platform built on V8 to build network applications", currentVersion: "21.7.1", type: .formula, homepage: "https://nodejs.org", license: "MIT"),
            FormulaItem(id: "python@3.11", name: "python@3.11", fullTitle: "Python 3.11", description: "Interpreted, object-oriented, high-level programming language", currentVersion: "3.11.8", type: .formula, homepage: "https://www.python.org", license: "Python-2.0"),
            FormulaItem(id: "wireshark", name: "Wireshark", fullTitle: "Wireshark", description: "Network traffic and protocol analyzer", currentVersion: "4.2.4", type: .cask, homepage: "https://www.wireshark.org")
        ]
    }
}
