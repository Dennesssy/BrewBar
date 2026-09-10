import Foundation

@MainActor
public final class BrewService: ObservableObject {
    public static let shared = BrewService()

    @Published public private(set) var installedPackages: [FormulaItem] = []
    @Published public private(set) var availableUpdates: [FormulaItem] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: BrewBarError?
    @Published public private(set) var lastHomebrewUpdate: Date?
    @Published public private(set) var isUpdatingHomebrew: Bool = false
    @Published public private(set) var isCleaningUp: Bool = false

    private let processManager = ProcessManager()
    private let outputParser = OutputParser()
    private let errorHandler = ErrorHandler()

    public init() {}

    public func installFormula(_ name: String, type: PackageType? = nil) async throws {
        guard validateFormulaName(name) else {
            let err = BrewBarError.invalidFormulaName(name)
            self.lastError = err
            throw err
        }
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).install(name, type: type)
        do {
            _ = try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments())
            self.lastError = nil
            try await refreshInstalledPackages()
        } catch {
            let handled = errorHandler.handle(error)
            self.lastError = handled
            throw handled
        }
    }

    public func upgradeFormula(_ name: String, type: PackageType? = nil) async throws {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).upgrade(name, type: type)
        do {
            _ = try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments())
            self.lastError = nil
            try await refreshInstalledPackages()
            try await checkForUpdates()
        } catch {
            let handled = errorHandler.handle(error)
            self.lastError = handled
            throw handled
        }
    }

    public func upgradeAll() async throws {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).upgrade()
        do {
            _ = try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments())
            self.lastError = nil
            try await refreshInstalledPackages()
            try await checkForUpdates()
        } catch {
            let handled = errorHandler.handle(error)
            self.lastError = handled
            throw handled
        }
    }

    public func uninstallFormula(_ name: String, type: PackageType? = nil) async throws {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).uninstall(name, type: type)
        do {
            _ = try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments())
            self.lastError = nil
            try await refreshInstalledPackages()
            try await checkForUpdates()
        } catch {
            let handled = errorHandler.handle(error)
            self.lastError = handled
            throw handled
        }
    }

    public func refreshInstalledPackages() async throws {
        isLoading = true
        defer { isLoading = false }

        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).listInstalledInfo()

        do {
            let output = try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments())
            var packages = try outputParser.parseInstalledPackages(output)

            let sizes = await computeInstalledSizes(brewPath: prefs.homebrewPrefix)
            if !sizes.isEmpty {
                packages = packages.map { item in
                    guard let bytes = sizes[item.id] else { return item }
                    return FormulaItem(
                        id: item.id,
                        name: item.name,
                        fullTitle: item.fullTitle,
                        description: item.description,
                        currentVersion: item.currentVersion,
                        latestVersion: item.latestVersion,
                        type: item.type,
                        homepage: item.homepage,
                        repository: item.repository,
                        license: item.license,
                        sizeInBytes: bytes,
                        installedDate: item.installedDate,
                        lastChecked: item.lastChecked,
                        updateAvailable: item.updateAvailable,
                        isPinned: item.isPinned,
                        isAutoUpdateEnabled: item.isAutoUpdateEnabled,
                        dependencies: item.dependencies,
                        versions: item.versions
                    )
                }
            }

            self.installedPackages = packages
            self.lastError = nil

            // Index refreshed installed packages in macOS Spotlight
            Task {
                await SpotlightIndexer.shared.indexPackages(packages)
            }
        } catch {
            let handledError = errorHandler.handle(error)
            self.lastError = handledError
            throw handledError
        }
    }

    /// On-disk size per installed formula/cask, in bytes, keyed by id.
    /// `brew info` carries no size field at all, so this shells out to `du`
    /// over the real Cellar/Caskroom directories instead of guessing.
    private func computeInstalledSizes(brewPath: String) async -> [String: UInt64] {
        var sizes: [String: UInt64] = [:]
        // Route through BrewCommandBuilder so a preference stored as an
        // install prefix (e.g. "/opt/homebrew") rather than the brew
        // executable itself still resolves correctly, matching every other
        // call site.
        let resolvedBrewPath = BrewCommandBuilder(brewPath: brewPath).executablePath

        for flag in ["--cellar", "--caskroom"] {
            guard let dirPath = try? await processManager.execute(executablePath: resolvedBrewPath, arguments: [flag]) else {
                continue
            }
            let trimmedPath = dirPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: trimmedPath), !entries.isEmpty else {
                continue
            }

            let fullPaths = entries.map { "\(trimmedPath)/\($0)" }
            guard let duOutput = try? await processManager.execute(executablePath: "/usr/bin/du", arguments: ["-sk"] + fullPaths) else {
                continue
            }

            for line in duOutput.split(separator: "\n") {
                let parts = line.split(separator: "\t")
                guard parts.count == 2, let kilobytes = UInt64(parts[0]) else { continue }
                let name = String(parts[1].split(separator: "/").last ?? "")
                sizes[name] = kilobytes * 1024
            }
        }

        return sizes
    }

    /// `brew update` refreshes tap metadata; run this before relying on
    /// `checkForUpdates()` for accurate "outdated" results.
    public func updateHomebrew() async throws {
        isUpdatingHomebrew = true
        defer { isUpdatingHomebrew = false }

        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).update()

        do {
            _ = try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments(), timeout: 120)
            self.lastHomebrewUpdate = Date()
            self.lastError = nil
            try await checkForUpdates()
        } catch {
            let handled = errorHandler.handle(error)
            self.lastError = handled
            throw handled
        }
    }

    /// Runs `brew cleanup`. `dryRun: true` reports what would be removed
    /// (and how much space would be freed) without deleting anything.
    @discardableResult
    public func cleanup(dryRun: Bool) async throws -> String {
        isCleaningUp = true
        defer { isCleaningUp = false }

        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).cleanup(dryRun: dryRun)

        do {
            let output = try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments(), timeout: 120)
            self.lastError = nil
            if !dryRun {
                try await refreshInstalledPackages()
            }
            return output
        } catch {
            let handled = errorHandler.handle(error)
            self.lastError = handled
            throw handled
        }
    }

    public func checkForUpdates() async throws {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).outdated(json: true)

        do {
            let output = try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments())
            let (formulas, casks) = try outputParser.parseOutdatedPackages(output)

            var updates: [FormulaItem] = []

            for formula in formulas {
                updates.append(FormulaItem(
                    id: formula.name,
                    name: formula.name,
                    fullTitle: formula.full_name ?? formula.name,
                    description: formula.desc ?? "",
                    currentVersion: formula.installed_versions?.first ?? "",
                    latestVersion: formula.current_version,
                    type: .formula,
                    homepage: formula.homepage,
                    updateAvailable: true
                ))
            }

            for cask in casks {
                updates.append(FormulaItem(
                    id: cask.name,
                    name: cask.name,
                    fullTitle: cask.name,
                    currentVersion: cask.installed_versions?.first ?? "",
                    latestVersion: cask.current_version,
                    type: .cask,
                    updateAvailable: true
                ))
            }

            self.availableUpdates = updates

            let updateIds = Set(updates.map { $0.id })
            self.installedPackages = self.installedPackages.map { item in
                FormulaItem(
                    id: item.id,
                    name: item.name,
                    fullTitle: item.fullTitle,
                    description: item.description,
                    currentVersion: item.currentVersion,
                    latestVersion: item.latestVersion,
                    type: item.type,
                    homepage: item.homepage,
                    repository: item.repository,
                    license: item.license,
                    sizeInBytes: item.sizeInBytes,
                    installedDate: item.installedDate,
                    lastChecked: item.lastChecked,
                    updateAvailable: updateIds.contains(item.id),
                    isPinned: item.isPinned,
                    isAutoUpdateEnabled: item.isAutoUpdateEnabled,
                    dependencies: item.dependencies,
                    versions: item.versions
                )
            }
            self.lastError = nil
        } catch {
            let handledError = errorHandler.handle(error)
            self.lastError = handledError
            throw handledError
        }
    }

    private func validateFormulaName(_ name: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./@"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
