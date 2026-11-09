// Copyright © 2026 Dennis Stewart. All rights reserved.

import XCTest
@testable import BrewBarKit

final class ToolDiscoveryTests: XCTestCase {

    // MARK: - Catalog parsing

    func testParseInstalledFormulae() throws {
        let json = """
        {
            "formulae": [
                {
                    "name": "ripgrep",
                    "desc": "Search tool like grep and The Silver Searcher",
                    "installed": [{"version": "14.1.0"}, {"version": "15.2.0"}],
                    "linked_keg": "15.2.0"
                },
                {
                    "name": "jq",
                    "desc": null,
                    "installed": [{"version": "1.7.1"}],
                    "linked_keg": null
                },
                {
                    "name": "orphan",
                    "desc": "No installed versions",
                    "installed": [],
                    "linked_keg": null
                }
            ],
            "casks": [{"token": "some-cask"}]
        }
        """

        let formulae = try InstalledToolCatalog.parseInstalledFormulae(json)

        XCTAssertEqual(formulae.count, 2)
        XCTAssertEqual(formulae[0].name, "ripgrep")
        XCTAssertEqual(formulae[0].version, "15.2.0")
        XCTAssertEqual(formulae[0].desc, "Search tool like grep and The Silver Searcher")
        XCTAssertTrue(formulae[0].isLinked)
        XCTAssertEqual(formulae[1].name, "jq")
        XCTAssertEqual(formulae[1].version, "1.7.1")
        XCTAssertNil(formulae[1].desc)
        XCTAssertFalse(formulae[1].isLinked)
    }

    func testParseInstalledFormulaeRejectsGarbage() {
        XCTAssertThrowsError(try InstalledToolCatalog.parseInstalledFormulae("not json"))
    }

    // MARK: - Man page extraction

    func testManPageExtraction() {
        let text = """
        RG(1)                       General Commands Manual                      RG(1)

        NAME
               rg - recursively search current directory for lines matching a pattern

        SYNOPSIS
               rg [OPTIONS] PATTERN [PATH...]
               rg [OPTIONS] -e PATTERN... [PATH...]

        DESCRIPTION
               ripgrep (rg) recursively searches your current directory for a regex pattern.

        OPTIONS
               -i, --ignore-case
                      Case insensitive search.

               -m, --max-count=NUM
                      Limit the number of matching lines per file searched to NUM.

               -e, --regexp=PATTERN
                      A pattern to search for.

               -t, --type=TYPE
                      Only search files matching TYPE.

        ripgrep 15.2.0                   2026-01-01                          RG(1)
        """

        let tree = CommandTreeExtractor.parse(toolName: "rg", text: text)

        XCTAssertEqual(tree.name, "rg")
        XCTAssertEqual(tree.summary, "recursively search current directory for lines matching a pattern")
        XCTAssertEqual(tree.usage, ["rg [OPTIONS] PATTERN [PATH...]", "rg [OPTIONS] -e PATTERN... [PATH...]"])
        XCTAssertEqual(tree.options.count, 4)

        let ignoreCase = tree.options[0]
        XCTAssertEqual(ignoreCase.flags, ["-i", "--ignore-case"])
        XCTAssertNil(ignoreCase.argument)
        XCTAssertEqual(ignoreCase.summary, "Case insensitive search.")

        let maxCount = tree.options[1]
        XCTAssertEqual(maxCount.flags, ["-m", "--max-count"])
        XCTAssertEqual(maxCount.argument, "NUM")
        XCTAssertEqual(maxCount.summary, "Limit the number of matching lines per file searched to NUM.")

        let regexp = tree.options[2]
        XCTAssertEqual(regexp.flags, ["-e", "--regexp"])
        XCTAssertEqual(regexp.argument, "PATTERN")

        XCTAssertEqual(tree.options[3].argument, "TYPE")
        XCTAssertTrue(tree.subcommands.isEmpty)
    }

    // MARK: - --help extraction

    func testHelpFlagExtraction() {
        let text = """
        Recursively searches for a pattern in the current directory.

        Usage: mytool [OPTIONS] <PATTERN> [COMMAND]

        Commands:
          search   Search for a pattern in files
          index    Build the search index
          help     Print this message or the help of the given subcommand(s)

        Options:
          -v, --verbose          Use verbose output
          -c, --config <FILE>    Path to the config file
              --max-count=<NUM>  Stop after NUM matches
          -h, --help             Print help
          -V, --version          Print version
        """

        let tree = CommandTreeExtractor.parse(toolName: "mytool", text: text)

        XCTAssertEqual(tree.summary, "Recursively searches for a pattern in the current directory.")
        XCTAssertEqual(tree.usage, ["mytool [OPTIONS] <PATTERN> [COMMAND]"])

        XCTAssertEqual(tree.subcommands.map(\.name), ["search", "index", "help"])
        XCTAssertEqual(tree.subcommands[0].summary, "Search for a pattern in files")
        XCTAssertEqual(tree.subcommands[1].summary, "Build the search index")
        XCTAssertTrue(tree.subcommands[0].subcommands.isEmpty)

        XCTAssertEqual(tree.options.count, 5)
        XCTAssertEqual(tree.options[0].flags, ["-v", "--verbose"])
        XCTAssertNil(tree.options[0].argument)
        XCTAssertEqual(tree.options[1].flags, ["-c", "--config"])
        XCTAssertEqual(tree.options[1].argument, "FILE")
        XCTAssertEqual(tree.options[1].summary, "Path to the config file")
        XCTAssertEqual(tree.options[2].flags, ["--max-count"])
        XCTAssertEqual(tree.options[2].argument, "NUM")
        XCTAssertEqual(tree.options[3].flags, ["-h", "--help"])
    }

    func testDegenerateInputDoesNotCrash() {
        let empty = CommandTreeExtractor.parse(toolName: "x", text: "")
        XCTAssertNil(empty.summary)
        XCTAssertTrue(empty.options.isEmpty)
        XCTAssertTrue(empty.subcommands.isEmpty)

        let weird = CommandTreeExtractor.parse(toolName: "x", text: "-----\n\t\u{0}\n  -\n  --\nCOMMANDS\n  \t\n  - bad\n  Bad Name   x")
        XCTAssertTrue(weird.options.isEmpty)
        XCTAssertTrue(weird.subcommands.isEmpty)
    }

    // MARK: - Ranking

    func testSearchRanking() {
        let tools = [
            InstalledTool(name: "tool", formula: "misc", version: "1", path: "/p/tool", summary: "uses jq internally"),
            InstalledTool(name: "fx", formula: "jq-tools", version: "1", path: "/p/fx", summary: nil),
            InstalledTool(name: "gojq", formula: "gojq", version: "1", path: "/p/gojq", summary: nil),
            InstalledTool(name: "jql", formula: "jql", version: "1", path: "/p/jql", summary: nil),
            InstalledTool(name: "jq", formula: "jq", version: "1", path: "/p/jq", summary: "JSON processor"),
        ]

        let ranked = ToolDiscoveryService.rank(tools, query: "JQ", limit: 10)
        XCTAssertEqual(ranked.map(\.name), ["jq", "jql", "gojq", "fx", "tool"])

        let limited = ToolDiscoveryService.rank(tools, query: "jq", limit: 3)
        XCTAssertEqual(limited.map(\.name), ["jq", "jql", "gojq"])

        let unfiltered = ToolDiscoveryService.rank(tools, query: "", limit: 2)
        XCTAssertEqual(unfiltered.map(\.name), ["tool", "fx"])

        XCTAssertTrue(ToolDiscoveryService.rank(tools, query: "jq", limit: 0).isEmpty)
    }

    func testCapabilityQueryRanksPrimaryToolAboveMidWordMatches() {
        let tools = [
            InstalledTool(name: "lzegrep", formula: "xz", version: "5.8", path: "/p/lzegrep", summary: "General-purpose data compression"),
            InstalledTool(name: "xzgrep", formula: "xz", version: "5.8", path: "/p/xzgrep", summary: "General-purpose data compression"),
            InstalledTool(name: "semgrep", formula: "semgrep", version: "1", path: "/p/semgrep", summary: "Detect and prevent bugs"),
            InstalledTool(name: "rg", formula: "ripgrep", version: "15", path: "/p/rg", summary: "Search tool like grep and The Silver Searcher"),
            InstalledTool(name: "ggrep", formula: "grep", version: "3", path: "/p/ggrep", summary: "GNU grep, egrep and fgrep"),
        ]

        let top3 = ToolDiscoveryService.rank(tools, query: "grep", limit: 3).map(\.name)
        XCTAssertTrue(top3.contains("rg"))
        XCTAssertTrue(top3.contains("ggrep"))

        let ranked = ToolDiscoveryService.rank(tools, query: "grep", limit: 10).map(\.name)
        guard let rgIndex = ranked.firstIndex(of: "rg"), let lzegrepIndex = ranked.firstIndex(of: "lzegrep") else {
            return XCTFail("rg or lzegrep missing from \(ranked)")
        }
        XCTAssertLessThan(rgIndex, lzegrepIndex)
    }

    func testJsonQueryKeepsJqInTopThree() {
        let tools = [
            InstalledTool(name: "gpgme-json", formula: "gpgme", version: "1", path: "/p/gpgme-json", summary: "Library access to GnuPG"),
            InstalledTool(name: "jq", formula: "jq", version: "1", path: "/p/jq", summary: "Lightweight and flexible command-line JSON processor"),
            InstalledTool(name: "jless", formula: "jless", version: "1", path: "/p/jless", summary: "Command-line JSON viewer"),
            InstalledTool(name: "gojq", formula: "gojq", version: "1", path: "/p/gojq", summary: "Go implementation of jq"),
            InstalledTool(name: "curl", formula: "curl", version: "1", path: "/p/curl", summary: "Get a file from an HTTP server"),
        ]

        let top3 = ToolDiscoveryService.rank(tools, query: "json", limit: 3).map(\.name)
        XCTAssertTrue(top3.contains("jq"))
        XCTAssertFalse(top3.contains("curl"))
    }

    func testExactNameRanksFirst() {
        let tools = [
            InstalledTool(name: "curl", formula: "curl", version: "1", path: "/p/curl", summary: "Get a file from an HTTP server"),
            InstalledTool(name: "https", formula: "httpie", version: "1", path: "/p/https", summary: "cURL replacement (HTTP client)"),
            InstalledTool(name: "httpie", formula: "httpie", version: "1", path: "/p/httpie", summary: "cURL replacement (HTTP client)"),
            InstalledTool(name: "http", formula: "httpie", version: "1", path: "/p/http", summary: "cURL replacement (HTTP client)"),
            InstalledTool(name: "httpserv", formula: "nss", version: "1", path: "/p/httpserv", summary: nil),
        ]

        XCTAssertEqual(ToolDiscoveryService.rank(tools, query: "http", limit: 5).first?.name, "http")
    }

    func testSummaryWordPrefixFindsCompressionTools() {
        let tools = [
            InstalledTool(name: "gzip", formula: "gzip", version: "1", path: "/p/gzip", summary: "Popular GNU data compression program"),
            InstalledTool(name: "xz", formula: "xz", version: "1", path: "/p/xz", summary: "General-purpose data compression with high compression ratio"),
            InstalledTool(name: "zstd", formula: "zstd", version: "1", path: "/p/zstd", summary: "Zstandard is a real-time compression algorithm"),
            InstalledTool(name: "opj_compress", formula: "openjpeg", version: "1", path: "/p/opj_compress", summary: "Library for JPEG-2000 image manipulation"),
            InstalledTool(name: "uncompress", formula: "ncompress", version: "1", path: "/p/uncompress", summary: "Decode Lempel-Ziv files"),
        ]

        let top3 = ToolDiscoveryService.rank(tools, query: "compress", limit: 3).map(\.name)
        let compressors = top3.filter { ["gzip", "xz", "zstd"].contains($0) }
        XCTAssertGreaterThanOrEqual(compressors.count, 2)
    }

    // MARK: - Validation (no brew or man involved)

    func testDocumentationRejectsUnsafeName() async throws {
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToolDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        let service = ToolDiscoveryService(cacheDirectory: cache)

        do {
            _ = try await service.documentation(for: "../etc")
            XCTFail("Expected invalidToolName")
        } catch {
            XCTAssertEqual(error as? ToolDiscoveryError, ToolDiscoveryError.invalidToolName("../etc"))
        }
    }

    // MARK: - Live (opt-in: BREWBAR_LIVE=1)

    func testLiveSmoke() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREWBAR_LIVE"] == "1")

        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToolDiscoveryLive-\(UUID().uuidString)", isDirectory: true)
        let tool = ProcessInfo.processInfo.environment["BREWBAR_LIVE_TOOL"] ?? "rg"
        let service = ToolDiscoveryService(cacheDirectory: cache)
        let doc: ToolDocumentation
        do {
            doc = try await service.documentation(for: tool)
        } catch {
            try? FileManager.default.removeItem(at: cache)
            XCTFail("documentation(for: \(tool)) threw \(error)")
            return
        }
        try? FileManager.default.removeItem(at: cache)

        print("LIVE \(tool) source=\(doc.source.rawValue) options=\(doc.tree.options.count) subcommands=\(doc.tree.subcommands.count) summary=\(doc.tree.summary ?? "nil") rawChars=\(doc.rawText.count)")
        XCTAssertNotEqual(doc.source, .none)
        XCTAssertFalse(doc.tree.options.isEmpty)
    }

    func testLiveRankingTop5() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREWBAR_LIVE"] == "1")

        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToolRankingLive-\(UUID().uuidString)", isDirectory: true)
        let service = ToolDiscoveryService(cacheDirectory: cache)

        let grep = try await service.searchTools("grep", limit: 5).map(\.name)
        let json = try await service.searchTools("json", limit: 5).map(\.name)
        print("LIVE top5 grep=\(grep) json=\(json)")

        XCTAssertTrue(grep.contains("rg"))
        XCTAssertTrue(json.contains("jq"))
    }
}
