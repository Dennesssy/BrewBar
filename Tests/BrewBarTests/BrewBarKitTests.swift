// Copyright © 2026 Dennis Stewart. All rights reserved.

import XCTest
@testable import BrewBarKit

final class BrewBarKitTests: XCTestCase {

    func testBrewCommandBuilder() {
        let builder = BrewCommandBuilder(brewPath: "/usr/local/bin/brew")

        let installBuilder = builder.install("python")
        XCTAssertEqual(installBuilder.executablePath, "/usr/local/bin/brew")
        XCTAssertEqual(installBuilder.buildArguments(), ["install", "python"])

        let listBuilder = builder.listInstalledInfo()
        XCTAssertEqual(listBuilder.buildArguments(), ["info", "--installed", "--json=v2"])

        let outdatedBuilder = builder.outdated(json: true)
        XCTAssertEqual(outdatedBuilder.buildArguments(), ["outdated", "--json=v2"])
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

    func testParseNewPackagesFromBrewUpdateOutput() {
        // Real `brew update` wraps long lists across multiple
        // whitespace-separated lines rather than always one name per line.
        let output = """
        ==> Updating Homebrew...
        Updated 2 taps (homebrew/core and homebrew/cask).
        ==> New Formulae
        foo-cli bar-tool
        baz-lang
        ==> New Casks
        some-app
        ==> Outdated Formulae
        git
        """

        let (formulae, casks) = BrewService.parseNewPackages(from: output)
        XCTAssertEqual(formulae, ["foo-cli", "bar-tool", "baz-lang"])
        XCTAssertEqual(casks, ["some-app"])
    }

    func testParseNewPackagesWhenUpToDate() {
        let output = """
        ==> Updating Homebrew...
        Already up-to-date.
        """
        let (formulae, casks) = BrewService.parseNewPackages(from: output)
        XCTAssertTrue(formulae.isEmpty)
        XCTAssertTrue(casks.isEmpty)
    }

    func testStorageRowUninstallTargetRoutesThroughBrew() {
        // Cellar/Caskroom top-level entries must resolve to a brew
        // uninstall target — deleting their files directly would leave
        // Homebrew's install receipts pointing at nothing.
        let formulaRow = StorageRow(name: "wget", path: "/opt/homebrew/Cellar/wget", sizeInBytes: 100, isDirectory: true, kind: .cellarFormula)
        XCTAssertEqual(formulaRow.uninstallTarget?.name, "wget")
        XCTAssertEqual(formulaRow.uninstallTarget?.type, .formula)
        XCTAssertFalse(formulaRow.isDirectlyTrashable)

        let caskRow = StorageRow(name: "docker", path: "/opt/homebrew/Caskroom/docker", sizeInBytes: 100, isDirectory: true, kind: .caskApp)
        XCTAssertEqual(caskRow.uninstallTarget?.type, .cask)
    }

    func testStorageRowNestedTrashability() {
        // Only cache/log entries are safe to delete directly; a version
        // folder nested inside Cellar/Caskroom is not.
        let cacheFile = StorageRow(name: "wget-1.21.3.tar.gz", path: "/tmp/cache/wget-1.21.3.tar.gz", sizeInBytes: 50, isDirectory: false, kind: .nested(trashable: true))
        XCTAssertTrue(cacheFile.isDirectlyTrashable)
        XCTAssertNil(cacheFile.uninstallTarget)

        let cellarVersionFolder = StorageRow(name: "1.21.3", path: "/opt/homebrew/Cellar/wget/1.21.3", sizeInBytes: 50, isDirectory: true, kind: .nested(trashable: false))
        XCTAssertFalse(cellarVersionFolder.isDirectlyTrashable)
        XCTAssertNil(cellarVersionFolder.uninstallTarget)
    }

    func testStorageRowIsNavigableOnlyForDirectories() {
        let dir = StorageRow(name: "Cellar", path: "/opt/homebrew/Cellar", sizeInBytes: 0, isDirectory: true, kind: .category(.cellar))
        let file = StorageRow(name: "archive.tar.gz", path: "/tmp/archive.tar.gz", sizeInBytes: 0, isDirectory: false, kind: .nested(trashable: true))
        XCTAssertTrue(dir.isNavigable)
        XCTAssertFalse(file.isNavigable)
    }

    func testBrewCommandBuilderOperations() {
        let builder = BrewCommandBuilder(brewPath: "/usr/local/bin/brew")
        
        XCTAssertEqual(builder.tap("homebrew/core").buildArguments(), ["tap", "homebrew/core"])
        XCTAssertEqual(builder.untap("homebrew/core").buildArguments(), ["untap", "homebrew/core"])
        XCTAssertEqual(builder.pin("python").buildArguments(), ["pin", "python"])
        XCTAssertEqual(builder.unpin("python").buildArguments(), ["unpin", "python"])
        XCTAssertEqual(builder.autoremove(dryRun: false).buildArguments(), ["autoremove"])
        XCTAssertEqual(builder.autoremove(dryRun: true).buildArguments(), ["autoremove", "-n"])
        XCTAssertEqual(builder.reinstall("python", type: .formula).buildArguments(), ["reinstall", "--formula", "python"])
        XCTAssertEqual(builder.link("python").buildArguments(), ["link", "python"])
        XCTAssertEqual(builder.unlink("python").buildArguments(), ["unlink", "python"])
        XCTAssertEqual(builder.bundleDump(file: "Brewfile").buildArguments(), ["bundle", "dump", "--file=Brewfile"])
        XCTAssertEqual(builder.bundleInstall(file: "Brewfile").buildArguments(), ["bundle", "install", "--file=Brewfile"])
    }

    func testOutputParserDoctorConfig() throws {
        let parser = OutputParser()
        
        let doctorJson = """
        [
            {
                "warning": "You have unlinked kegs in your Cellar.\\nLeaving kegs unlinked can lead to build-trouble and cause formulae that depend on those kegs to fail to run properly once built.\\n\\n  node"
            }
        ]
        """
        let doctorJsonIssues = parser.parseDoctor(doctorJson)
        XCTAssertEqual(doctorJsonIssues.count, 1)
        XCTAssertEqual(doctorJsonIssues[0].severity, .warning)
        XCTAssertTrue(doctorJsonIssues[0].summary.contains("unlinked kegs"))
        
        let doctorText = """
        Please note that these warnings are just used to help the Homebrew maintainers
        with debugging if you file an issue. If everything you use Homebrew for is
        working fine: please don't worry or file an issue; just ignore this. Thanks!
        
        Warning: You have unlinked kegs in your Cellar.
        Leaving kegs unlinked can lead to build-trouble and cause formulae that depend on those kegs to fail to run properly once built.
        
          node
        """
        let doctorTextIssues = parser.parseDoctor(doctorText)
        XCTAssertEqual(doctorTextIssues.count, 1)
        XCTAssertEqual(doctorTextIssues[0].severity, .warning)
        XCTAssertTrue(doctorTextIssues[0].summary.contains("unlinked kegs"))
        
        let configOutput = """
        HOMEBREW_VERSION: 4.1.0
        ORIGIN: https://github.com/Homebrew/brew
        HOMEBREW_PREFIX: /opt/homebrew
        HOMEBREW_REPOSITORY: /opt/homebrew
        HOMEBREW_CELLAR: /opt/homebrew/Cellar
        """
        let configSections = parser.parseConfig(configOutput)
        XCTAssertGreaterThan(configSections.count, 0)
    }

    func testVulnsJsonParser() {
        let parser = OutputParser()
        let json = """
        {
          "vulnerabilities": [
            {
              "name": "openssl@3",
              "version": "3.1.4",
              "vulnerabilities": [
                {
                  "id": "CVE-2023-5678",
                  "summary": "Poly1305 MAC invalid on Windows",
                  "severity": "High",
                  "fixed_in": "3.1.5"
                }
              ]
            }
          ],
          "skipped": [
            {
              "name": "custom-pkg",
              "reason": "Not from a recognized tap"
            }
          ]
        }
        """
        
        let (vulns, skipped) = parser.parseVulnsJSON(json)
        XCTAssertEqual(vulns.count, 1)
        XCTAssertEqual(vulns[0].package, "openssl@3")
        XCTAssertEqual(vulns[0].vulnerabilities.count, 1)
        XCTAssertEqual(vulns[0].vulnerabilities[0].cve, "CVE-2023-5678")
        XCTAssertEqual(vulns[0].vulnerabilities[0].fixedIn, "3.1.5")
        
        XCTAssertEqual(skipped.count, 1)
        XCTAssertEqual(skipped[0].package, "custom-pkg")
        
        let emptyJson = "{}"
        let (emptyVulns, emptySkipped) = parser.parseVulnsJSON(emptyJson)
        XCTAssertEqual(emptyVulns.count, 0)
        XCTAssertEqual(emptySkipped.count, 0)
        
        let malformedJson = "{ vulnerabilities: [}"
        let (malformedVulns, malformedSkipped) = parser.parseVulnsJSON(malformedJson)
        XCTAssertEqual(malformedVulns.count, 0)
        XCTAssertEqual(malformedSkipped.count, 0)
    }
}
