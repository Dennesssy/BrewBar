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
}
