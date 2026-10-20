// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

// Shared contract for local tool discovery. Consumed by:
//   - ToolDiscoveryService  (catalog + man/--help extraction + cache)
//   - MCPServer             (exposes discovery to terminal agents over stdio)
//   - SkillGenerator        (writes ~/.brewbar/skills/<tool>/SKILL.md)
// Keep these types Codable + Sendable: they are cached to disk and sent as
// MCP tool results verbatim.

/// One executable a Homebrew formula linked into `<prefix>/bin`.
/// A formula can ship several (e.g. `ripgrep` → `rg`, `coreutils` → `gls`, …).
public struct InstalledTool: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name }
    /// Executable name as typed in a terminal (`rg`).
    public let name: String
    /// Owning formula (`ripgrep`).
    public let formula: String
    public let version: String
    /// Absolute path inside the keg, e.g. `/opt/homebrew/Cellar/ripgrep/15.2.0/bin/rg`.
    public let path: String
    public let summary: String?

    public init(name: String, formula: String, version: String, path: String, summary: String?) {
        self.name = name
        self.formula = formula
        self.version = version
        self.path = path
        self.summary = summary
    }
}

public struct CommandOption: Codable, Sendable, Hashable {
    /// All spellings, e.g. `["-i", "--ignore-case"]`.
    public let flags: [String]
    /// Placeholder for a value-taking option (`FILE`, `<n>`), nil for booleans.
    public let argument: String?
    public let summary: String

    public init(flags: [String], argument: String?, summary: String) {
        self.flags = flags
        self.argument = argument
        self.summary = summary
    }
}

/// A command or subcommand. `git` → children `commit`, `push`, …
public struct CommandNode: Codable, Sendable, Hashable {
    public let name: String
    public let summary: String?
    public let usage: [String]
    public let options: [CommandOption]
    public let subcommands: [CommandNode]

    public init(name: String, summary: String?, usage: [String], options: [CommandOption], subcommands: [CommandNode]) {
        self.name = name
        self.summary = summary
        self.usage = usage
        self.options = options
        self.subcommands = subcommands
    }
}

public enum ToolDocSource: String, Codable, Sendable {
    case manPage
    case helpFlag
    case none
}

/// Full documentation snapshot for one tool; this is what gets cached.
public struct ToolDocumentation: Codable, Sendable {
    public let tool: InstalledTool
    public let source: ToolDocSource
    /// Plain text (overstrikes stripped). Empty when `source == .none`.
    public let rawText: String
    public let tree: CommandNode
    public let generatedAt: Date

    public init(tool: InstalledTool, source: ToolDocSource, rawText: String, tree: CommandNode, generatedAt: Date) {
        self.tool = tool
        self.source = source
        self.rawText = rawText
        self.tree = tree
        self.generatedAt = generatedAt
    }
}

public protocol ToolDiscoveryProviding: Sendable {
    /// Every executable linked from installed formulae. Cheap after first call.
    func listTools() async throws -> [InstalledTool]
    /// Case-insensitive match over name, formula and summary; best first.
    func searchTools(_ query: String, limit: Int) async throws -> [InstalledTool]
    /// Man page if present, else `--help`. Served from cache when the tool's
    /// version is unchanged.
    func documentation(for toolName: String) async throws -> ToolDocumentation
}

public protocol SkillWriting: Sendable {
    /// Renders `doc` to `<skillsRoot>/<tool>/SKILL.md`, overwriting. Returns the file URL.
    func writeSkill(for doc: ToolDocumentation) async throws -> URL
}

public enum ToolDiscoveryError: Error, Sendable, Equatable {
    case toolNotFound(String)
    case invalidToolName(String)
}

/// `~/.brewbar` layout. Created lazily; never written outside this root.
public enum BrewBarPaths {
    /// `BREWBAR_HOME` overrides the location (tests, sandboxed agents).
    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["BREWBAR_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".brewbar", isDirectory: true)
    }
    public static var skills: URL { root.appendingPathComponent("skills", isDirectory: true) }
    public static var docCache: URL { root.appendingPathComponent("cache/docs", isDirectory: true) }

    /// Tool names become directory names; reject anything that could escape.
    public static func isSafeComponent(_ name: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.+@"))
        return !name.isEmpty && name != "." && name != ".." && !name.hasPrefix(".")
            && name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
