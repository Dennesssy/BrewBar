import Foundation

@MainActor
public final class BrewService: ObservableObject {
    public static let shared = BrewService()

    @Published public private(set) var installedPackages: [FormulaItem] = []
    @Published public private(set) var availableUpdates: [FormulaItem] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: BrewBarError?

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
            let packages = try outputParser.parseInstalledPackages(output)
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
                let name = cask.name?.first ?? cask.token
                updates.append(FormulaItem(
                    id: cask.token,
                    name: name,
                    fullTitle: cask.token,
                    description: cask.desc ?? "",
                    currentVersion: cask.installed_versions?.first ?? "",
                    latestVersion: cask.current_version,
                    type: .cask,
                    homepage: cask.homepage,
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
