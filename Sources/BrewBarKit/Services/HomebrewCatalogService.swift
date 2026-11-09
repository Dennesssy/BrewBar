// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// Matches the real `formulae.brew.sh/api/formula.json` schema (verified
/// against live output — same shape as `brew info`'s formula entries).
public struct CatalogFormula: Codable, Sendable {
    public let name: String
    public let desc: String?
    public let homepage: String?
    public let license: String?
    public let versions: CatalogVersions?
    public let deprecated: Bool?
    public let disabled: Bool?

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
    public let deprecated: Bool?
    public let disabled: Bool?
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
    private var popularityIndex: [String: Int] = [:]
    private var searchIndex: [SearchEntry] = []
    private var lastLoadedAt: Date?
    private var loadTask: Task<Void, Never>?

    private struct SearchEntry {
        let item: FormulaItem
        let name: String
        let id: String
        let title: String
        let desc: String
    }

    nonisolated private static let catalogTTL: TimeInterval = 60 * 60 * 24

    public init() {}

    public var hasLoaded: Bool { !formulaByName.isEmpty }

    public func loadIfNeeded() async {
        if hasLoaded, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < Self.catalogTTL {
            return
        }
        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refresh()
        }
        loadTask = task
        await task.value
        loadTask = nil
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
                if f.deprecated == true || f.disabled == true { continue }
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
            lastError = nil
        } else if formulaByName.isEmpty {
            lastError = .networkError("Could not load the Homebrew formula catalog.")
        } else {
            lastError = nil
        }

        if let caskList {
            var map: [String: FormulaItem] = [:]
            map.reserveCapacity(caskList.count)
            for c in caskList {
                if c.deprecated == true || c.disabled == true { continue }
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

        rebuildSearchIndex()
        if hasLoaded {
            lastLoadedAt = Date()
        }
    }

    /// Local, ranked search across every formula and cask. Runs against the
    /// in-memory index so results appear as the user types, without hitting
    /// the network or depending on `brew search`.
    public func search(_ query: String, limit: Int = 60) -> [FormulaItem] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return [] }
        let tokens = clean.split(whereSeparator: \.isWhitespace).map(String.init)

        var scored: [(item: FormulaItem, score: Int)] = []
        for entry in searchIndex {
            guard let score = matchScore(entry, clean: clean, tokens: tokens) else { continue }
            scored.append((entry.item, score))
        }

        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            let ra = popularityIndex[a.item.id] ?? Int.max
            let rb = popularityIndex[b.item.id] ?? Int.max
            if ra != rb { return ra < rb }
            return a.item.name.localizedCaseInsensitiveCompare(b.item.name) == .orderedAscending
        }

        return scored.prefix(limit).map(\.item)
    }

    private func rebuildSearchIndex() {
        var entries: [SearchEntry] = []
        entries.reserveCapacity(formulaByName.count + caskByToken.count)
        for item in formulaByName.values {
            entries.append(makeSearchEntry(item))
        }
        for item in caskByToken.values {
            entries.append(makeSearchEntry(item))
        }
        searchIndex = entries

        var popularity: [String: Int] = [:]
        for (index, id) in topFormulaIds.prefix(600).enumerated() {
            popularity[id] = index
        }
        for (index, id) in topCaskIds.prefix(600).enumerated() {
            popularity[id] = index
        }
        popularityIndex = popularity
    }

    private func makeSearchEntry(_ item: FormulaItem) -> SearchEntry {
        SearchEntry(
            item: item,
            name: item.name.lowercased(),
            id: item.id.lowercased(),
            title: (item.fullTitle ?? "").lowercased(),
            desc: item.description.lowercased()
        )
    }

    private func matchScore(_ entry: SearchEntry, clean: String, tokens: [String]) -> Int? {
        let score: Int
        if entry.name == clean || entry.id == clean {
            score = 1_000
        } else if entry.name.hasPrefix(clean) || entry.id.hasPrefix(clean) {
            score = 800
        } else if entry.name.contains(clean) || entry.id.contains(clean) {
            score = 650
        } else if entry.title.contains(clean) {
            score = 520
        } else if tokens.allSatisfy({ entry.name.contains($0) || entry.id.contains($0) || entry.title.contains($0) }) {
            score = 420
        } else if tokens.allSatisfy({ entry.desc.contains($0) }) {
            score = 220
        } else {
            return nil
        }

        let popularityBonus = popularityIndex[entry.item.id].map { max(0, 120 - $0 / 8) } ?? 0
        return score + popularityBonus
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

    /// Decoding the ~50 MB catalog must not happen on the main actor.
    private nonisolated func fetchCached<T: Decodable & Sendable>(key: String, url: URL) async -> T? {
        if let cached = await CacheManager.shared.cachedData(forKey: key),
           let decoded = try? JSONDecoder().decode(T.self, from: cached) {
            return decoded
        }
        do {
            let data = try await HTTPClient.shared.fetchRawData(url)
            guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
                return nil
            }
            await CacheManager.shared.cacheData(data, forKey: key, ttl: Self.catalogTTL)
            return decoded
        } catch {
            Logger.shared.error("Catalog fetch failed for \(url.absoluteString): \(error.localizedDescription)")
            // An expired cache still beats an empty Discover page when the
            // network is unavailable.
            if let stale = await CacheManager.shared.staleData(forKey: key),
               let decoded = try? JSONDecoder().decode(T.self, from: stale) {
                Logger.shared.warning("Using stale cached catalog for \(url.absoluteString)")
                return decoded
            }
            return nil
        }
    }
}
