// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// Read-only discovery of installed CLI tools and their documentation.
/// Documentation comes from `man -P cat <tool>` when available, else `<keg>/bin/<tool> --help`.
public actor ToolDiscoveryService: ToolDiscoveryProviding {
    private static let catalogTTL: TimeInterval = 60
    private static let commandTimeout: TimeInterval = 10
    private static let manExecutable = "/usr/bin/man"
    private static let sandboxExecutable = "/usr/bin/sandbox-exec"
    private static let helpSandboxProfile = """
        (version 1)(allow default)(deny network*)\
        (deny file-write* (require-not (literal "/dev/null")))
        """

    private let catalog: InstalledToolCatalog
    private let cacheDirectory: URL
    private var cachedTools: [InstalledTool]?
    private var cachedAt: Date?

    public init(brewPath: String = HomebrewPath.defaultBrewExecutable, cacheDirectory: URL = BrewBarPaths.docCache) {
        self.catalog = InstalledToolCatalog(brewPath: brewPath)
        self.cacheDirectory = cacheDirectory
    }

    public func listTools() async throws -> [InstalledTool] {
        if let tools = cachedTools, let at = cachedAt, Date().timeIntervalSince(at) < Self.catalogTTL {
            return tools
        }
        let tools = try await catalog.loadTools()
        cachedTools = tools
        cachedAt = Date()
        return tools
    }

    public func searchTools(_ query: String, limit: Int) async throws -> [InstalledTool] {
        let tools = try await listTools()
        return Self.rank(tools, query: query, limit: limit)
    }

    /// Additive, deterministic score. Each field takes its best tier only:
    ///   name:    exact 100 · prefix 60 · word start 40 · mid-word 10
    ///   formula: exact 50  · prefix 30 · word start 20 · mid-word 15
    ///   summary: whole word 30 · word prefix 20 · mid-word 5
    ///   primary binary (name == formula) +10, only when something else matched.
    /// Mid-word name hits are the noisiest class (substrings of unrelated words), so they
    /// sit below any word-boundary hit. A word prefix in a summary ("compress" in
    /// "compression") is a word-boundary match, weaker than the exact word.
    /// Sort: score desc, then shorter name, then alphabetical. An empty query returns
    /// the first `limit` tools in catalog order.
    static func rank(_ tools: [InstalledTool], query: String, limit: Int) -> [InstalledTool] {
        guard limit > 0 else { return [] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return Array(tools.prefix(limit)) }

        let scored: [(tool: InstalledTool, score: Int)] = tools.compactMap { tool in
            let score = matchScore(tool, needle: needle)
            return score > 0 ? (tool, score) : nil
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.tool.name.count != rhs.tool.name.count { return lhs.tool.name.count < rhs.tool.name.count }
                return lhs.tool.name < rhs.tool.name
            }
            .prefix(limit)
            .map(\.tool)
    }

    private static func matchScore(_ tool: InstalledTool, needle: String) -> Int {
        let name = tool.name.lowercased()
        let formula = tool.formula.lowercased()
        var score = 0

        if name == needle {
            score += 100
        } else if name.hasPrefix(needle) {
            score += 60
        } else if words(in: name).contains(where: { $0.hasPrefix(needle) }) {
            score += 40
        } else if name.contains(needle) {
            score += 10
        }

        if formula == needle {
            score += 50
        } else if formula.hasPrefix(needle) {
            score += 30
        } else if words(in: formula).contains(where: { $0.hasPrefix(needle) }) {
            score += 20
        } else if formula.contains(needle) {
            score += 15
        }

        if let summary = tool.summary?.lowercased() {
            if words(in: summary).contains(where: { $0 == needle }) {
                score += 30
            } else if words(in: summary).contains(where: { $0.hasPrefix(needle) }) {
                score += 20
            } else if summary.contains(needle) {
                score += 5
            }
        }

        guard score > 0 else { return 0 }
        return tool.name == tool.formula ? score + 10 : score
    }

    private static func words(in text: String) -> [Substring] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }

    public func documentation(for toolName: String) async throws -> ToolDocumentation {
        guard BrewBarPaths.isSafeComponent(toolName) else {
            throw ToolDiscoveryError.invalidToolName(toolName)
        }
        let tools = try await listTools()
        guard let tool = tools.first(where: { $0.name == toolName }) else {
            throw ToolDiscoveryError.toolNotFound(toolName)
        }

        if let cached = readCache(named: toolName), cached.tool.version == tool.version, cached.tool.path == tool.path {
            return ToolDocumentation(
                tool: tool,
                source: cached.source,
                rawText: cached.rawText,
                tree: cached.tree,
                generatedAt: cached.generatedAt
            )
        }

        let (source, text) = await extractText(for: tool)
        let document = ToolDocumentation(
            tool: tool,
            source: source,
            rawText: text,
            tree: CommandTreeExtractor.parse(toolName: tool.name, text: text),
            generatedAt: Date()
        )
        writeCache(document)
        return document
    }

    // MARK: - Extraction

    private func extractText(for tool: InstalledTool) async -> (ToolDocSource, String) {
        let manOutput = try? await ProcessManager().execute(
            executablePath: Self.manExecutable,
            arguments: ["-P", "cat", tool.name],
            timeout: Self.commandTimeout,
            allowNonZeroExit: true,
            extraEnvironment: ["MANWIDTH": "100"]
        )
        if let manOutput, !manOutput.isEmpty, !manOutput.contains("No manual entry") {
            return (.manPage, ManPageText.stripOverstrike(manOutput))
        }

        // Only the absolute path from the catalog (inside the Cellar); never a PATH lookup.
        guard tool.path.hasPrefix("/") else { return (.none, "") }
        // Not every binary honors --help: some treat it as a filename or just
        // run (observed: keygen/dictionary tools writing files into the cwd).
        // Run it under a sandbox with no file writes and no network.
        let helpOutput = try? await ProcessManager().execute(
            executablePath: Self.sandboxExecutable,
            arguments: ["-p", Self.helpSandboxProfile, tool.path, "--help"],
            timeout: Self.commandTimeout,
            allowNonZeroExit: true
        )
        if let helpOutput, !helpOutput.isEmpty {
            return (.helpFlag, ManPageText.stripOverstrike(helpOutput))
        }
        return (.none, "")
    }

    // MARK: - Cache

    private func cacheFileURL(named name: String) -> URL {
        cacheDirectory.appendingPathComponent("\(name).json")
    }

    private func readCache(named name: String) -> ToolDocumentation? {
        guard let data = try? Data(contentsOf: cacheFileURL(named: name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ToolDocumentation.self, from: data)
    }

    /// Best-effort: a cache that cannot be written only costs a re-extraction next time.
    private func writeCache(_ document: ToolDocumentation) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(document) else { return }
        try? data.write(to: cacheFileURL(named: document.tool.name), options: .atomic)
    }
}
