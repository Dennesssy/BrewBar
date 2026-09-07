import XCTest
@testable import BrewBarKit

final class BrewBarKitTests: XCTestCase {

    func testBrewCommandBuilder() {
        let builder = BrewCommandBuilder(brewPath: "/usr/local/bin/brew")
        let installCmd = builder.install("python").build()
        XCTAssertEqual(installCmd, "/usr/local/bin/brew install python")

        let listCmd = builder.listInstalledInfo().build()
        XCTAssertEqual(listCmd, "/usr/local/bin/brew info --installed --json=v2")

        let outdatedCmd = builder.outdated(json: true).build()
        XCTAssertEqual(outdatedCmd, "/usr/local/bin/brew outdated --json=v2")
    }

    func testOutputParser() throws {
        let json = """
        {
            "formulae": [
                {
                    "name": "git",
                    "full_name": "git",
                    "desc": "Distributed revision control system",
                    "installed_versions": ["2.42.0"],
                    "homepage": "https://git-scm.com"
                }
            ],
            "casks": [
                {
                    "token": "visual-studio-code",
                    "name": ["Visual Studio Code"],
                    "desc": "Open-source code editor",
                    "installed_versions": ["1.85.0"],
                    "homepage": "https://code.visualstudio.com"
                }
            ]
        }
        """

        let parser = OutputParser()
        let items = try parser.parseInstalledPackages(json)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "git")
        XCTAssertEqual(items[0].type, .formula)
        XCTAssertEqual(items[1].name, "Visual Studio Code")
        XCTAssertEqual(items[1].type, .cask)
    }

    func testVersionComparator() {
        XCTAssertTrue(VersionComparator.isOutdated(current: "1.0.0", latest: "1.0.1"))
        XCTAssertFalse(VersionComparator.isOutdated(current: "2.0.0", latest: "1.9.9"))
        XCTAssertEqual(VersionComparator.compare("3.11.0", "3.11.0"), .orderedSame)
    }

    func testFormulaItemInitialization() {
        let item = FormulaItem(
            id: "rust",
            name: "rust",
            description: "Empowering everyone to build reliable and efficient software",
            currentVersion: "1.77.0",
            type: .formula
        )

        XCTAssertEqual(item.id, "rust")
        XCTAssertEqual(item.currentVersion, "1.77.0")
        XCTAssertFalse(item.updateAvailable)
    }

    func testSemanticSearchAndRanking() {
        let items = [
            FormulaItem(id: "python@3.11", name: "python@3.11", description: "Interpreted high-level language", currentVersion: "3.11.8", type: .formula),
            FormulaItem(id: "postgresql@16", name: "postgresql@16", description: "Object-relational database system", currentVersion: "16.2", type: .formula),
            FormulaItem(id: "visual-studio-code", name: "visual-studio-code", description: "Popular open source code editor", currentVersion: "1.85.0", type: .cask)
        ]

        // Test alias expansion & semantic lookup for "database"
        let dbResults = SemanticSearchEngine.searchAndRank(items: items, query: "database")
        XCTAssertFalse(dbResults.isEmpty)
        XCTAssertEqual(dbResults.first?.id, "postgresql@16")

        // Test alias expansion for "py" -> "python"
        let pyResults = SemanticSearchEngine.searchAndRank(items: items, query: "py")
        XCTAssertFalse(pyResults.isEmpty)
        XCTAssertEqual(pyResults.first?.id, "python@3.11")

        // Test "editor" -> "visual-studio-code"
        let editorResults = SemanticSearchEngine.searchAndRank(items: items, query: "editor")
        XCTAssertFalse(editorResults.isEmpty)
        XCTAssertEqual(editorResults.first?.id, "visual-studio-code")
    }

    func testUpdateAvailabilityReconciliation() {
        // Simulates the reconciliation logic in BrewService.checkForUpdates()
        let installedPackages = [
            FormulaItem(id: "git", name: "git", description: "Distributed revision control system", currentVersion: "2.42.0", type: .formula),
            FormulaItem(id: "node", name: "node", description: "Platform built on V8", currentVersion: "20.0.0", type: .formula),
            FormulaItem(id: "python@3.11", name: "python@3.11", description: "Interpreted language", currentVersion: "3.11.8", type: .formula),
            FormulaItem(id: "visual-studio-code", name: "visual-studio-code", description: "Code editor", currentVersion: "1.85.0", type: .cask)
        ]

        // Only git and visual-studio-code have updates available
        let availableUpdates = [
            FormulaItem(id: "git", name: "git", description: "Distributed revision control system", currentVersion: "2.42.0", latestVersion: "2.43.0", type: .formula, updateAvailable: true),
            FormulaItem(id: "visual-studio-code", name: "visual-studio-code", description: "Code editor", currentVersion: "1.85.0", latestVersion: "1.86.0", type: .cask, updateAvailable: true)
        ]

        // Reconcile update availability into installed packages (mirroring BrewService logic)
        let updateIds = Set(availableUpdates.map { $0.id })
        let reconciledPackages = installedPackages.map { item in
            let hasUpdate = updateIds.contains(item.id)
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
                sizeInBytes: item.sizeInBytes,
                installedDate: item.installedDate,
                lastChecked: item.lastChecked,
                updateAvailable: hasUpdate,
                isPinned: item.isPinned,
                isAutoUpdateEnabled: item.isAutoUpdateEnabled,
                dependencies: item.dependencies,
                versions: item.versions
            )
        }

        // Verify packages with updates are marked correctly
        let gitPackage = reconciledPackages.first { $0.id == "git" }
        XCTAssertNotNil(gitPackage)
        XCTAssertTrue(gitPackage!.updateAvailable, "git should have updateAvailable = true")

        let vscodePackage = reconciledPackages.first { $0.id == "visual-studio-code" }
        XCTAssertNotNil(vscodePackage)
        XCTAssertTrue(vscodePackage!.updateAvailable, "visual-studio-code should have updateAvailable = true")

        // Verify packages without updates are marked correctly
        let nodePackage = reconciledPackages.first { $0.id == "node" }
        XCTAssertNotNil(nodePackage)
        XCTAssertFalse(nodePackage!.updateAvailable, "node should have updateAvailable = false")

        let pythonPackage = reconciledPackages.first { $0.id == "python@3.11" }
        XCTAssertNotNil(pythonPackage)
        XCTAssertFalse(pythonPackage!.updateAvailable, "python@3.11 should have updateAvailable = false")
    }

    // MARK: - CacheManager Tests

    func testCacheManagerDistinguishesSlashFromUnderscore() async {
        let cacheManager = CacheManager()

        // Clear any existing cache
        await cacheManager.clearAllCache()

        // Store data with keys that would collide under the old lossy encoding
        let dataWithSlash = "data for formula/foo".data(using: .utf8)!
        let dataWithUnderscore = "data for formula_foo".data(using: .utf8)!

        await cacheManager.cacheData(dataWithSlash, forKey: "formula/foo")
        await cacheManager.cacheData(dataWithUnderscore, forKey: "formula_foo")

        // Retrieve and verify they remain distinct
        let retrievedSlash = await cacheManager.cachedData(forKey: "formula/foo")
        let retrievedUnderscore = await cacheManager.cachedData(forKey: "formula_foo")

        XCTAssertNotNil(retrievedSlash, "Data for 'formula/foo' should be retrievable")
        XCTAssertNotNil(retrievedUnderscore, "Data for 'formula_foo' should be retrievable")

        XCTAssertEqual(retrievedSlash, dataWithSlash, "Data for 'formula/foo' should match what was stored")
        XCTAssertEqual(retrievedUnderscore, dataWithUnderscore, "Data for 'formula_foo' should match what was stored")

        // Verify the values are different (not colliding)
        XCTAssertNotEqual(retrievedSlash, retrievedUnderscore, "Keys 'formula/foo' and 'formula_foo' must produce distinct cache entries")
    }

    func testCacheManagerRoundTrip() async {
        let cacheManager = CacheManager()

        await cacheManager.clearAllCache()

        let testKeys = [
            "simple",
            "with/slash",
            "with_underscore",
            "multiple/slashes/here",
            "mixed/slash_and_underscore",
            "cask/homebrew/cask/visual-studio-code",
            "formula_info"
        ]

        // Store data for each key
        for key in testKeys {
            let data = "value for \(key)".data(using: .utf8)!
            await cacheManager.cacheData(data, forKey: key)
        }

        // Verify each key retrieves its correct value
        for key in testKeys {
            let expectedData = "value for \(key)".data(using: .utf8)!
            let retrievedData = await cacheManager.cachedData(forKey: key)

            XCTAssertNotNil(retrievedData, "Should retrieve data for key '\(key)'")
            XCTAssertEqual(retrievedData, expectedData, "Retrieved data should match for key '\(key)'")
        }
    }

    func testCacheManagerClearAllCache() async {
        let cacheManager = CacheManager()

        // Store some data
        let data = "test data".data(using: .utf8)!
        await cacheManager.cacheData(data, forKey: "test/key")

        // Verify it was stored
        let beforeClear = await cacheManager.cachedData(forKey: "test/key")
        XCTAssertNotNil(beforeClear)

        // Clear and verify it's gone
        await cacheManager.clearAllCache()
        let afterClear = await cacheManager.cachedData(forKey: "test/key")
        XCTAssertNil(afterClear, "Cache should be empty after clearAllCache()")
    }
}
