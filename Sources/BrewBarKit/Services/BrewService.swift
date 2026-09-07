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

    public func installFormula(_ name: String) async throws {
        guard validateFormulaName(name) else {
            throw BrewBarError.invalidFormulaName(name)
        }
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let cmd = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).install(name).build()
        _ = try await processManager.execute(command: cmd)
        try await refreshInstalledPackages()
    }

    public func upgradeFormula(_ name: String) async throws {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let cmd = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).upgrade(name).build()
        _ = try await processManager.execute(command: cmd)
        try await refreshInstalledPackages()
        try await checkForUpdates()
    }

    public func upgradeAll() async throws {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let cmd = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).upgrade().build()
        _ = try await processManager.execute(command: cmd)
        try await refreshInstalledPackages()
        try await checkForUpdates()
    }

    public func uninstallFormula(_ name: String) async throws {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let cmd = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).uninstall(name).build()
        _ = try await processManager.execute(command: cmd)
        try await refreshInstalledPackages()
    }

    public func refreshInstalledPackages() async throws {
        isLoading = true
        defer { isLoading = false }

        let prefs = await LocalStorageManager.shared.loadPreferences()
        let cmd = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).listInstalledInfo().build()

        do {
            let output = try await processManager.execute(command: cmd)
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
        let cmd = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).outdated(json: true).build()

        do {
            let output = try await processManager.execute(command: cmd)
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
