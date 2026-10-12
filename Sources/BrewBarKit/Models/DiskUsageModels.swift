// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// The real on-disk locations Homebrew itself manages, resolved via
/// `brew --cellar` / `--caskroom` / `--cache` (never assumed) so a custom
/// install prefix set in Preferences is always respected.
public enum DiskUsageCategory: String, Sendable, CaseIterable, Identifiable, Codable {
    case cellar = "Cellar"
    case caskroom = "Caskroom"
    case downloadCache = "Download Cache"
    case logs = "Logs"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .cellar: return "shippingbox"
        case .caskroom: return "app.badge"
        case .downloadCache: return "arrow.down.circle"
        case .logs: return "doc.text"
        }
    }

    public var subtitle: String {
        switch self {
        case .cellar: return "Installed formula files"
        case .caskroom: return "Installed cask app bundles"
        case .downloadCache: return "Cached downloads — safe to clear, Homebrew re-fetches on demand"
        case .logs: return "Build and install logs"
        }
    }
}

/// A single row in the ncdu-style drill-down: either one of the four
/// category roots, a top-level package directory inside Cellar/Caskroom, or
/// any nested file/folder underneath.
public struct StorageRow: Sendable, Identifiable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// One of the four top-level roots (Cellar, Caskroom, Download Cache, Logs).
        case category(DiskUsageCategory)
        /// A direct child of Cellar — its name is an installed formula's name.
        /// Deleting it must go through `brew uninstall`, never a raw file
        /// delete, or Homebrew's own receipt bookkeeping goes stale.
        case cellarFormula
        /// A direct child of Caskroom — its name is an installed cask's token.
        case caskApp
        /// Anything nested deeper (a formula's version folder, a cached
        /// archive, a log file) — browsable, and directly trashable only
        /// when it lives under Download Cache or Logs.
        case nested(trashable: Bool)
    }

    public let id: String // full filesystem path — unique by construction
    public let name: String
    public let path: String
    public let sizeInBytes: UInt64
    public let isDirectory: Bool
    public let kind: Kind

    public init(name: String, path: String, sizeInBytes: UInt64, isDirectory: Bool, kind: Kind) {
        self.id = path
        self.name = name
        self.path = path
        self.sizeInBytes = sizeInBytes
        self.isDirectory = isDirectory
        self.kind = kind
    }

    public var isNavigable: Bool { isDirectory }

    /// Formula/cask name to hand to `BrewService.uninstallFormula`, and
    /// which package type it is — only meaningful for `.cellarFormula`/`.caskApp`.
    public var uninstallTarget: (name: String, type: PackageType)? {
        switch kind {
        case .cellarFormula: return (name, .formula)
        case .caskApp: return (name, .cask)
        default: return nil
        }
    }

    public var isDirectlyTrashable: Bool {
        if case .nested(let trashable) = kind { return trashable }
        return false
    }
}
