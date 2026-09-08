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
}
