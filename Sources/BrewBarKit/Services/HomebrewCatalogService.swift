import Foundation

/// Matches the real `formulae.brew.sh/api/formula.json` schema (verified
/// against live output — same shape as `brew info`'s formula entries).
public struct CatalogFormula: Codable, Sendable {
    public let name: String
    public let desc: String?
    public let homepage: String?
    public let license: String?
    public let versions: CatalogVersions?

    public struct CatalogVersions: Codable, Sendable {
        public let stable: String?
    }
}

/// Matches `formulae.brew.sh/api/cask.json`.
public struct CatalogCask: Codable, Sendable {
    public let token: String
    public let name: [String]?
    public let desc: String?
    public let homepage: String?
    public let version: String?
}

/// Matches `formulae.brew.sh/api/analytics/install/30d.json` and
/// `.../cask-install/30d.json` — real 30-day install-count rankings.
public struct AnalyticsResult: Codable, Sendable {
    public let items: [AnalyticsItem]
}

public struct AnalyticsItem: Codable, Sendable {
    public let formula: String?
    public let cask: String?
    public let count: String?
}

/// Loads and caches the full real Homebrew catalog (~8,600 formulas, ~7,700
/// casks) plus real install-popularity rankings, replacing the hand-written
/// curated lists that previously stood in for "Discover" content. Backed by
/// `CacheManager`'s disk cache with a 24h TTL so the ~50MB payload isn't
/// re-downloaded on every launch.
@MainActor
public final class HomebrewCatalogService: ObservableObject {
    public static let shared = HomebrewCatalogService()

    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: BrewBarError?
    @Published public private(set) var totalFormulaCount: Int = 0
    @Published public private(set) var totalCaskCount: Int = 0

    private var formulaByName: [String: FormulaItem] = [:]
    private var caskByToken: [String: FormulaItem] = [:]
    private var topFormulaIds: [String] = []
    private var topCaskIds: [String] = []

    private let httpClient = HTTPClient.shared
    private let cache = CacheManager.shared
    private let errorHandler = ErrorHandler()

    private static let catalogTTL: TimeInterval = 60 * 60 * 24

    public init() {}

    public var hasLoaded: Bool { !formulaByName.isEmpty }

    public func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let formulas: [CatalogFormula]? = fetchCached(
            key: "catalog_formula_v1",
            url: URL(string: "https://formulae.brew.sh/api/formula.json")!
        )
        async let casks: [CatalogCask]? = fetchCached(
            key: "catalog_cask_v1",
            url: URL(string: "https://formulae.brew.sh/api/cask.json")!
        )
        async let formulaAnalytics: AnalyticsResult? = fetchCached(
            key: "catalog_analytics_formula_v1",
            url: URL(string: "https://formulae.brew.sh/api/analytics/install/30d.json")!
        )
        async let caskAnalytics: AnalyticsResult? = fetchCached(
            key: "catalog_analytics_cask_v1",
            url: URL(string: "https://formulae.brew.sh/api/analytics/cask-install/30d.json")!
        )

        let (formulaList, caskList, formulaRank, caskRank) = await (formulas, casks, formulaAnalytics, caskAnalytics)

        if let formulaList {
            var map: [String: FormulaItem] = [:]
            map.reserveCapacity(formulaList.count)
            for f in formulaList {
                map[f.name] = FormulaItem(
                    id: f.name,
                    name: f.name,
                    fullTitle: f.name,
                    description: f.desc ?? "",
                    currentVersion: f.versions?.stable ?? "",
                    type: .formula,
                    homepage: f.homepage,
                    license: f.license
                )
            }
            formulaByName = map
            totalFormulaCount = map.count
        } else if formulaByName.isEmpty {
            lastError = .networkError("Could not load the Homebrew formula catalog.")
        }

        if let caskList {
            var map: [String: FormulaItem] = [:]
            map.reserveCapacity(caskList.count)
            for c in caskList {
                map[c.token] = FormulaItem(
                    id: c.token,
                    name: c.name?.first ?? c.token,
                    fullTitle: c.name?.first ?? c.token,
                    description: c.desc ?? "",
                    currentVersion: c.version ?? "",
                    type: .cask,
                    homepage: c.homepage
                )
            }
            caskByToken = map
            totalCaskCount = map.count
        }

        if let formulaRank {
            topFormulaIds = formulaRank.items.compactMap { $0.formula }
        }
        if let caskRank {
            topCaskIds = caskRank.items.compactMap { $0.cask }
        }
    }

    public func formula(id: String) -> FormulaItem? {
        formulaByName[id]
    }

    public func cask(id: String) -> FormulaItem? {
        caskByToken[id]
    }

    /// Looks up an id as either a formula or a cask (callers resolving a
    /// name from `brew update`'s output don't know which it is ahead of time).
    public func lookup(id: String) -> FormulaItem? {
        formulaByName[id] ?? caskByToken[id]
    }

    public func topFormulas(limit: Int) -> [FormulaItem] {
        topFormulaIds.compactMap { formulaByName[$0] }.prefix(limit).map { $0 }
    }

    public func topCasks(limit: Int) -> [FormulaItem] {
        topCaskIds.compactMap { caskByToken[$0] }.prefix(limit).map { $0 }
    }

    /// Real formulas/casks whose description or name matches any of the
    /// given keywords, ranked by real install popularity where known
    /// (unranked matches sort last, alphabetically) — replaces the 3
    /// hand-picked, hand-described items each category previously had.
    public func formulasMatching(keywords: [String], limit: Int) -> [FormulaItem] {
        rank(matching(formulaByName.values, keywords: keywords), by: topFormulaIds, limit: limit)
    }

    public func casksMatching(keywords: [String], limit: Int) -> [FormulaItem] {
        rank(matching(caskByToken.values, keywords: keywords), by: topCaskIds, limit: limit)
    }

    private func matching(_ items: Dictionary<String, FormulaItem>.Values, keywords: [String]) -> [FormulaItem] {
        guard !keywords.isEmpty else { return Array(items) }
        return items.filter { item in
            let haystack = (item.description + " " + item.name).lowercased()
            return keywords.contains { haystack.contains($0) }
        }
    }

    private func rank(_ items: [FormulaItem], by ranking: [String], limit: Int) -> [FormulaItem] {
        let rankIndex = Dictionary(uniqueKeysWithValues: ranking.enumerated().map { ($1, $0) })
        return items
            .sorted { a, b in
                let ra = rankIndex[a.id] ?? Int.max
                let rb = rankIndex[b.id] ?? Int.max
                if ra != rb { return ra < rb }
                return a.name.lowercased() < b.name.lowercased()
            }
            .prefix(limit)
            .map { $0 }
    }

    private func fetchCached<T: Decodable>(key: String, url: URL) async -> T? {
        if let cached = await cache.cachedData(forKey: key),
           let decoded = try? JSONDecoder().decode(T.self, from: cached) {
            return decoded
        }
        do {
            let data = try await httpClient.fetchRawData(url)
            guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
                return nil
            }
            await cache.cacheData(data, forKey: key, ttl: Self.catalogTTL)
            return decoded
        } catch {
            Logger.shared.error("Catalog fetch failed for \(url.absoluteString): \(error.localizedDescription)")
            return nil
        }
    }
}
