import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

public actor SpotlightIndexer {
    public static let shared = SpotlightIndexer()

    private let domainIdentifier = "com.dennesssy.brewbar.packages"

    public init() {}

    public func indexPackages(_ items: [FormulaItem]) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }

        let searchableItems = items.map { item -> CSSearchableItem in
            let attributeSet = CSSearchableItemAttributeSet(contentType: .item)
            attributeSet.title = item.name
            attributeSet.displayName = item.fullTitle ?? item.name
            attributeSet.contentDescription = item.description
            attributeSet.keywords = [item.name, item.type.rawValue, "homebrew", "brew", "package"] + (item.homepage != nil ? [item.homepage!] : [])

            return CSSearchableItem(
                uniqueIdentifier: "brewbar:\(item.type.rawValue):\(item.id)",
                domainIdentifier: domainIdentifier,
                attributeSet: attributeSet
            )
        }

        do {
            try await CSSearchableIndex.default().indexSearchableItems(searchableItems)
            Logger.shared.debug("Successfully indexed \(searchableItems.count) packages into Spotlight")
        } catch {
            Logger.shared.error("Failed to index packages in Spotlight: \(error.localizedDescription)")
        }
    }

    public func removePackageFromIndex(id: String, type: PackageType) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let identifier = "brewbar:\(type.rawValue):\(id)"
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [identifier])
            Logger.shared.debug("Removed package '\(identifier)' from Spotlight index")
        } catch {
            Logger.shared.error("Failed to remove package from Spotlight: \(error.localizedDescription)")
        }
    }

    public func clearAllIndexedPackages() async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier])
            Logger.shared.debug("Cleared all BrewBar packages from Spotlight index")
        } catch {
            Logger.shared.error("Failed to clear Spotlight index: \(error.localizedDescription)")
        }
    }
}

public struct SemanticSearchEngine: Sendable {
    public init() {}

    // Semantic term mappings for Homebrew packages & common user intents
    private static let semanticAliases: [String: [String]] = [
        "python": ["py", "python3", "pip", "anaconda", "jupyter", "scripting"],
        "node": ["nodejs", "js", "javascript", "npm", "nvm", "express"],
        "javascript": ["js", "node", "nodejs", "npm", "typescript", "ts"],
        "database": ["db", "postgres", "postgresql", "mysql", "sqlite", "redis", "mongodb", "mariadb"],
        "editor": ["vscode", "code", "vim", "neovim", "emacs", "sublime", "textedit", "ide"],
        "docker": ["container", "kubernetes", "k8s", "podman", "virtualization"],
        "git": ["vcs", "version control", "github", "gitlab", "commit"],
        "rust": ["cargo", "rustc", "systems programming"],
        "java": ["jdk", "jre", "openjdk", "maven", "gradle"],
        "network": ["curl", "wget", "http", "wireshark", "nmap", "proxy"]
    ]

    public static func calculateRelevanceScore(item: FormulaItem, query: String) -> Double {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanQuery.isEmpty else { return 0.0 }

        let nameLower = item.name.lowercased()
        let descLower = item.description.lowercased()
        let fullTitleLower = (item.fullTitle ?? "").lowercased()

        var score = 0.0

        // 1. Exact match on name
        if nameLower == cleanQuery {
            score += 100.0
        } else if nameLower.hasPrefix(cleanQuery) {
            score += 70.0
        } else if nameLower.contains(cleanQuery) {
            score += 40.0
        }

        // 2. Exact or substring match on full title
        if fullTitleLower.contains(cleanQuery) {
            score += 30.0
        }

        // 3. Substring match on description
        if descLower.contains(cleanQuery) {
            score += 20.0
        }

        // 4. Semantic alias matches
        for (term, aliases) in semanticAliases {
            if cleanQuery == term || aliases.contains(cleanQuery) {
                if nameLower.contains(term) || aliases.contains(where: { nameLower.contains($0) }) {
                    score += 25.0
                }
                if descLower.contains(term) || aliases.contains(where: { descLower.contains($0) }) {
                    score += 15.0
                }
            }
        }

        // 5. Fuzzy Levenshtein distance bonus for short queries
        let distance = levenshteinDistance(nameLower, cleanQuery)
        if distance <= 2 {
            score += Double(10 - (distance * 3))
        }

        return score
    }

    public static func searchAndRank(items: [FormulaItem], query: String) -> [FormulaItem] {
        let scoredItems = items.compactMap { item -> (FormulaItem, Double)? in
            let score = calculateRelevanceScore(item: item, query: query)
            guard score > 5.0 else { return nil }
            return (item, score)
        }

        return scoredItems.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var dist = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)

        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }

        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }

        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(dist[i - 1][j] + 1, dist[i][j - 1] + 1, dist[i - 1][j - 1] + 1)
                }
            }
        }

        return dist[a.count][b.count]
    }
}
