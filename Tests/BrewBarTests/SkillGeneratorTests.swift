// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation
import XCTest
@testable import BrewBarKit

final class SkillGeneratorTests: XCTestCase {

    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillGeneratorTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
        super.tearDown()
    }

    func testFrontmatterHasNameAndSingleLineQuotedDescription() {
        let doc = makeDoc(summary: "Fast \"grep\": line\nsearch")
        let lines = SkillGenerator.render(doc).components(separatedBy: "\n")

        XCTAssertEqual(lines[0], "---")
        XCTAssertEqual(lines[1], "name: rg")
        XCTAssertTrue(lines[2].hasPrefix("description: \""))
        XCTAssertTrue(lines[2].hasSuffix("\""))
        XCTAssertTrue(lines[2].contains("Fast \\\"grep\\\": line search"))
        XCTAssertEqual(lines[3], "---")
    }

    func testDescriptionIsCappedAt200Characters() {
        let doc = makeDoc(summary: String(repeating: "word ", count: 200))
        let line = SkillGenerator.render(doc).components(separatedBy: "\n")[2]
        let raw = String(line.dropFirst("description: \"".count).dropLast())

        XCTAssertLessThanOrEqual(raw.count, 200)
        XCTAssertTrue(raw.hasSuffix("Load before composing rg commands."))
    }

    func testOptionsTableEscapesPipesAndNewlines() {
        let option = CommandOption(flags: ["-x"], argument: "FILE", summary: "pipe | inside\nnewline")
        let text = SkillGenerator.render(makeDoc(options: [option]))

        XCTAssertTrue(text.contains("| `-x` | `FILE` | pipe \\| inside newline |\n"))
    }

    func testEmptySectionsAreOmitted() {
        let text = SkillGenerator.render(makeDoc())

        XCTAssertFalse(text.contains("## Usage"))
        XCTAssertFalse(text.contains("## Options"))
        XCTAssertFalse(text.contains("## Subcommands"))
        XCTAssertTrue(text.contains("## Full reference"))
    }

    func testNestedSubcommandsRenderAsIndentedBullets() {
        let amend = CommandNode(name: "amend", summary: "Amend last", usage: [], options: [], subcommands: [])
        let commit = CommandNode(name: "commit", summary: "Record changes", usage: [], options: [], subcommands: [amend])
        let push = CommandNode(name: "push", summary: nil, usage: [], options: [], subcommands: [])
        let text = SkillGenerator.render(makeDoc(subcommands: [commit, push]))
        let lines = text.components(separatedBy: "\n")

        XCTAssertTrue(lines.contains("- `commit` — Record changes"))
        XCTAssertTrue(lines.contains("  - `amend` — Amend last"))
        XCTAssertTrue(lines.contains("- `push`"))
    }

    func testOptionsTruncatedAt80Rows() {
        let options = (0..<85).map {
            CommandOption(flags: ["--opt\($0)"], argument: nil, summary: "Option \($0)")
        }
        let text = SkillGenerator.render(makeDoc(options: options))
        let rows = text.components(separatedBy: "\n").filter { $0.hasPrefix("| `") }

        XCTAssertEqual(rows.count, 80)
        XCTAssertTrue(text.contains("`--opt79`"))
        XCTAssertFalse(text.contains("`--opt80`"))
        XCTAssertTrue(text.contains("_…5 more options — see full reference._"))
    }

    func testWriteSkillWritesToRootNameSkillMarkdown() async throws {
        let generator = SkillGenerator(skillsRoot: root)
        let doc = makeDoc()

        let url = try await generator.writeSkill(for: doc)

        XCTAssertEqual(url.standardizedFileURL, root.appendingPathComponent("rg/SKILL.md").standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), SkillGenerator.render(doc))
    }

    func testWriteSkillRejectsUnsafeNames() async {
        let generator = SkillGenerator(skillsRoot: root)

        for name in ["../evil", ".hidden"] {
            do {
                _ = try await generator.writeSkill(for: makeDoc(name: name))
                XCTFail("Expected invalidToolName for \(name)")
            } catch {
                XCTAssertEqual(error as? ToolDiscoveryError, .invalidToolName(name))
            }
        }
    }

    func testWriteIndexListsToolsSortedByName() throws {
        let tools = [
            InstalledTool(name: "rg", formula: "ripgrep", version: "15.2.0",
                          path: "/opt/homebrew/Cellar/ripgrep/15.2.0/bin/rg", summary: "Search tool"),
            InstalledTool(name: "gls", formula: "coreutils", version: "9.5",
                          path: "/opt/homebrew/Cellar/coreutils/9.5/bin/gls", summary: nil),
            InstalledTool(name: "bat", formula: "bat", version: "0.24",
                          path: "/opt/homebrew/Cellar/bat/0.24/bin/bat", summary: "Cat clone")
        ]

        let url = try SkillGenerator(skillsRoot: root).writeIndex(tools: tools)

        XCTAssertEqual(url.lastPathComponent, "README.md")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), """
        # BrewBar skills

        Generated by BrewBar from installed Homebrew command-line tools. Each entry links to its SKILL.md.

        - [bat](bat/SKILL.md) — Cat clone (bat)
        - [gls](gls/SKILL.md) — installed command-line tool (coreutils)
        - [rg](rg/SKILL.md) — Search tool (ripgrep)

        """)
    }

    // MARK: - Fixtures

    private func makeDoc(
        name: String = "rg",
        summary: String? = "Search files",
        options: [CommandOption] = [],
        subcommands: [CommandNode] = [],
        source: ToolDocSource = .manPage
    ) -> ToolDocumentation {
        let tool = InstalledTool(
            name: name,
            formula: "ripgrep",
            version: "15.2.0",
            path: "/opt/homebrew/Cellar/ripgrep/15.2.0/bin/rg",
            summary: summary
        )
        let tree = CommandNode(name: name, summary: summary, usage: [], options: options, subcommands: subcommands)
        return ToolDocumentation(tool: tool, source: source, rawText: "", tree: tree, generatedAt: Date(timeIntervalSince1970: 0))
    }
}
