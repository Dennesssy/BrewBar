// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// Powers the ncdu-style Storage tab: resolves Homebrew's real on-disk
/// directories (Cellar, Caskroom, download cache, logs) and reports their
/// sizes via `du`, the same tool the `ncdu` CLI itself wraps — so numbers
/// here match what a user would see running `ncdu` on these paths by hand.
public actor DiskUsageService {
    public static let shared = DiskUsageService()

    private let processManager = ProcessManager()

    public init() {}

    /// Resolves each category's real root path. Missing directories (e.g.
    /// no cask ever installed, so no Caskroom) are simply omitted rather
    /// than reported as zero-byte.
    public func categoryRoots(brewPath: String) async -> [DiskUsageCategory: String] {
        let resolvedBrewPath = BrewCommandBuilder(brewPath: brewPath).executablePath
        var roots: [DiskUsageCategory: String] = [:]

        let flagsByCategory: [(String, DiskUsageCategory)] = [
            ("--cellar", .cellar),
            ("--caskroom", .caskroom),
            ("--cache", .downloadCache)
        ]
        for (flag, category) in flagsByCategory {
            guard let output = try? await processManager.execute(executablePath: resolvedBrewPath, arguments: [flag]) else { continue }
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                roots[category] = path
            }
        }

        let logsPath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/Homebrew")
        if FileManager.default.fileExists(atPath: logsPath) {
            roots[.logs] = logsPath
        }

        return roots
    }

    /// Top-level summary: one row per resolved category with its total
    /// recursive size.
    public func categorySummary(brewPath: String) async -> [StorageRow] {
        let roots = await categoryRoots(brewPath: brewPath)
        guard !roots.isEmpty else { return [] }

        let sizes = await duSizes(forPaths: Array(roots.values))

        return DiskUsageCategory.allCases.compactMap { category in
            guard let path = roots[category] else { return nil }
            return StorageRow(name: category.rawValue, path: path, sizeInBytes: sizes[path] ?? 0, isDirectory: true, kind: .category(category))
        }
        .sorted { $0.sizeInBytes > $1.sizeInBytes }
    }

    /// Immediate children of `directoryPath`, each with its full recursive
    /// size, sorted largest first — the drill-down list for a category or a
    /// nested folder. `category` and `isTopLevel` decide how each child is
    /// tagged (an installed formula/cask directory vs. a plain nested file)
    /// so the view knows which delete action, if any, is safe to offer.
    public func entries(in directoryPath: String, category: DiskUsageCategory, isTopLevel: Bool) async -> [StorageRow] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directoryPath), !names.isEmpty else {
            return []
        }

        let fullPaths = names.map { "\(directoryPath)/\($0)" }
        let sizes = await duSizes(forPaths: fullPaths)

        var rows: [StorageRow] = []
        rows.reserveCapacity(names.count)
        for (name, path) in zip(names, fullPaths) {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }

            let kind: StorageRow.Kind
            if isTopLevel {
                switch category {
                case .cellar: kind = .cellarFormula
                case .caskroom: kind = .caskApp
                case .downloadCache, .logs: kind = .nested(trashable: true)
                }
            } else {
                let trashable = (category == .downloadCache || category == .logs)
                kind = .nested(trashable: trashable)
            }

            rows.append(StorageRow(name: name, path: path, sizeInBytes: sizes[path] ?? 0, isDirectory: isDir.boolValue, kind: kind))
        }

        return rows.sorted { $0.sizeInBytes > $1.sizeInBytes }
    }

    /// Batched `du -sk` over every given path in a single process launch —
    /// shelling out once per row would mean one subprocess per Cellar
    /// formula, which gets slow fast on a machine with hundreds installed.
    private func duSizes(forPaths paths: [String]) async -> [String: UInt64] {
        guard !paths.isEmpty else { return [:] }
        guard let output = try? await processManager.execute(executablePath: "/usr/bin/du", arguments: ["-sk"] + paths) else {
            return [:]
        }

        var sizes: [String: UInt64] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let kilobytes = UInt64(parts[0]) else { continue }
            sizes[String(parts[1])] = kilobytes * 1024
        }
        return sizes
    }

    /// Moves a cache/log file or directory to the Trash (recoverable, not a
    /// permanent delete). Only ever called for `.nested(trashable: true)`
    /// rows — Cellar/Caskroom entries must go through `brew uninstall`
    /// instead, so Homebrew's own install receipts stay consistent.
    public func trash(path: String) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }
}
