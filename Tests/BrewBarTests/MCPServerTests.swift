// Copyright © 2026 Dennis Stewart. All rights reserved.

import XCTest
@testable import BrewBarKit

final class MCPServerTests: XCTestCase {

    // MARK: - Protocol envelope

    func testInitializeEchoesNumericAndStringIds() async throws {
        let server = makeServer()

        let numericLine = await server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#)
        let numeric = try XCTUnwrap(numericLine)
        XCTAssertTrue(numeric.contains(#""id":1,"#), "integral id must not gain a fraction: \(numeric)")
        let numericResponse = try parse(numeric)
        XCTAssertEqual(numericResponse["id"] as? Int, 1)
        let result = try XCTUnwrap(numericResponse["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "brewbar")
        XCTAssertNotNil(result["instructions"] as? String)

        let stringResponse = try await respond(server, #"{"jsonrpc":"2.0","id":"a","method":"initialize"}"#)
        XCTAssertEqual(stringResponse["id"] as? String, "a")
        let defaulted = try XCTUnwrap(stringResponse["result"] as? [String: Any])
        XCTAssertEqual(defaulted["protocolVersion"] as? String, "2025-06-18")
    }

    func testNotificationReturnsNil() async {
        let server = makeServer()
        let initialized = await server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(initialized)
        let idlessRequest = await server.handle(line: #"{"jsonrpc":"2.0","method":"ping"}"#)
        XCTAssertNil(idlessRequest)
        let blank = await server.handle(line: "   ")
        XCTAssertNil(blank)
    }

    func testMalformedJSONReturnsParseError() async throws {
        let server = makeServer()
        let response = try await respond(server, "{not json")
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32700)
        XCTAssertTrue(response["id"] is NSNull)
    }

    func testUnknownMethodReturnsMethodNotFound() async throws {
        let server = makeServer()
        let response = try await respond(server, #"{"jsonrpc":"2.0","id":7,"method":"nope/nope"}"#)
        XCTAssertEqual(response["id"] as? Int, 7)
        XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testPingReturnsEmptyResult() async throws {
        let response = try await respond(makeServer(), #"{"jsonrpc":"2.0","id":3,"method":"ping"}"#)
        XCTAssertEqual((response["result"] as? [String: Any])?.isEmpty, true)
    }

    // MARK: - tools/list

    func testToolsListDependsOnSkillsAvailability() async throws {
        let line = #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#

        let withSkills = try await respond(makeServer(skills: FakeSkills()), line)
        let withNames = try toolNames(withSkills)
        XCTAssertEqual(withNames.count, 4)
        XCTAssertEqual(Set(withNames), ["list_tools", "get_command_tree", "get_man_page", "generate_skill"])

        let withoutSkills = try await respond(makeServer(skills: nil), line)
        let withoutNames = try toolNames(withoutSkills)
        XCTAssertEqual(withoutNames.count, 3)
        XCTAssertFalse(withoutNames.contains("generate_skill"))
    }

    // MARK: - list_tools

    func testListToolsFiltersByQuery() async throws {
        let server = makeServer()
        let search = try await callTool(server, name: "list_tools", arguments: #"{"query":"SEARCH"}"#)
        XCTAssertFalse(search.isError)
        let matches = try parseArray(search.text)
        XCTAssertEqual(matches.compactMap { $0["name"] as? String }, ["rg"])
        XCTAssertEqual(matches.first?["formula"] as? String, "ripgrep")
        XCTAssertEqual(matches.first?["version"] as? String, "14.1.0")

        let all = try await callTool(server, name: "list_tools")
        XCTAssertEqual(try parseArray(all.text).count, 3)

        let limited = try await callTool(server, name: "list_tools", arguments: #"{"limit":1}"#)
        XCTAssertEqual(try parseArray(limited.text).count, 1)
    }

    func testListToolsRejectsNonIntegerLimit() async throws {
        let result = try await callTool(makeServer(), name: "list_tools", arguments: #"{"limit":"ten"}"#)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("limit"))
    }

    // MARK: - get_command_tree

    func testCommandTreeDepthPruning() async throws {
        let server = makeServer()

        let depthOne = try await callTool(server, name: "get_command_tree", arguments: #"{"tool":"git","depth":1}"#)
        let rootOnly = try parse(depthOne.text)
        XCTAssertEqual(rootOnly["name"] as? String, "git")
        XCTAssertEqual(rootOnly["source"] as? String, "manPage")
        XCTAssertEqual((rootOnly["options"] as? [Any])?.count, 1)
        XCTAssertEqual((rootOnly["subcommands"] as? [Any])?.count, 0)

        let defaultDepth = try await callTool(server, name: "get_command_tree", arguments: #"{"tool":"git"}"#)
        let twoLevels = try parse(defaultDepth.text)
        let subcommands = try XCTUnwrap(twoLevels["subcommands"] as? [[String: Any]])
        XCTAssertEqual(subcommands.compactMap { $0["name"] as? String }, ["commit", "remote"])
        let remote = try XCTUnwrap(subcommands.last)
        XCTAssertEqual((remote["subcommands"] as? [Any])?.count, 0, "depth 2 must prune grandchildren")

        let depthThree = try await callTool(server, name: "get_command_tree", arguments: #"{"tool":"git","depth":3}"#)
        let threeLevels = try parse(depthThree.text)
        let deepRemote = try XCTUnwrap((threeLevels["subcommands"] as? [[String: Any]])?.last)
        let leaves = try XCTUnwrap(deepRemote["subcommands"] as? [[String: Any]])
        XCTAssertEqual(leaves.compactMap { $0["name"] as? String }, ["add"])
    }

    // MARK: - get_man_page

    func testManPageSlicesLinesWithHeader() async throws {
        let result = try await callTool(makeServer(), name: "get_man_page", arguments: #"{"tool":"git","offset":2,"limit":3}"#)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.text, "# git (manPage) lines 3-5 of 10\nline 2\nline 3\nline 4")
    }

    func testManPageDefaultsToFullFirstWindow() async throws {
        let result = try await callTool(makeServer(), name: "get_man_page", arguments: #"{"tool":"git"}"#)
        XCTAssertEqual(result.text.components(separatedBy: "\n").first, "# git (manPage) lines 1-10 of 10")
    }

    func testManPageOffsetPastEndIsEmptyNotCrash() async throws {
        let result = try await callTool(makeServer(), name: "get_man_page", arguments: #"{"tool":"git","offset":99}"#)
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.text.hasPrefix("# git (manPage) no lines at offset 99; 10 total"))
    }

    // MARK: - Tool errors

    func testUnknownToolIsToolErrorNotProtocolError() async throws {
        let server = makeServer()
        let result = try await callTool(server, name: "install_thing")
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("list_tools"))
    }

    func testMissingAndUnknownArgumentsAreToolErrors() async throws {
        let server = makeServer()
        let missing = try await callTool(server, name: "get_command_tree")
        XCTAssertTrue(missing.isError)
        XCTAssertTrue(missing.text.contains("tool"))

        let unknownTool = try await callTool(server, name: "get_man_page", arguments: #"{"tool":"nope"}"#)
        XCTAssertTrue(unknownTool.isError)
        XCTAssertTrue(unknownTool.text.contains("list_tools"))

        let unsafe = try await callTool(server, name: "get_command_tree", arguments: #"{"tool":"../etc"}"#)
        XCTAssertTrue(unsafe.isError)
    }

    func testToolsCallWithoutNameIsInvalidParams() async throws {
        let response = try await respond(makeServer(), #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{}}"#)
        XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    // MARK: - Resources

    func testResourcesListAndRead() async throws {
        let server = makeServer()

        let listed = try await respond(server, #"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#)
        let resources = try XCTUnwrap((listed["result"] as? [String: Any])?["resources"] as? [[String: Any]])
        XCTAssertEqual(resources.count, 3)
        let gitResource = try XCTUnwrap(resources.first { $0["name"] as? String == "git" })
        XCTAssertEqual(gitResource["uri"] as? String, "brewbar://tool/git")
        XCTAssertEqual(gitResource["mimeType"] as? String, "text/plain")

        let read = try await respond(server, #"{"jsonrpc":"2.0","id":6,"method":"resources/read","params":{"uri":"brewbar://tool/git"}}"#)
        let contents = try XCTUnwrap((read["result"] as? [String: Any])?["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.first?["text"] as? String, Fixtures.manText)
        XCTAssertEqual(contents.first?["uri"] as? String, "brewbar://tool/git")
    }

    func testResourcesReadUnknownUriIsInvalidParams() async throws {
        let server = makeServer()
        let unknownTool = try await respond(server, #"{"jsonrpc":"2.0","id":8,"method":"resources/read","params":{"uri":"brewbar://tool/nope"}}"#)
        XCTAssertEqual((unknownTool["error"] as? [String: Any])?["code"] as? Int, -32602)

        let wrongScheme = try await respond(server, #"{"jsonrpc":"2.0","id":9,"method":"resources/read","params":{"uri":"file:///etc/hosts"}}"#)
        XCTAssertEqual((wrongScheme["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    // MARK: - generate_skill

    func testGenerateSkillForOneTool() async throws {
        let skills = FakeSkills()
        let result = try await callTool(makeServer(skills: skills), name: "generate_skill", arguments: #"{"tool":"git"}"#)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.text, "/fake/skills/git/SKILL.md")
        let written = await skills.written
        XCTAssertEqual(written, ["git"])
    }

    func testGenerateSkillAllCountsAndCapsFailures() async throws {
        let skills = FakeSkills(failing: ["jq"])
        let result = try await callTool(makeServer(skills: skills), name: "generate_skill", arguments: #"{"all":true}"#)
        XCTAssertFalse(result.isError)

        let summary = try parse(result.text)
        XCTAssertEqual(summary["written"] as? Int, 2)
        XCTAssertEqual(summary["failed"] as? Int, 1)
        let failures = try XCTUnwrap(summary["failures"] as? [[String: Any]])
        XCTAssertEqual(failures.first?["tool"] as? String, "jq")

        let written = await skills.written
        XCTAssertEqual(written, ["git", "rg"])
    }

    func testGenerateSkillWithoutSkillsIsToolError() async throws {
        let result = try await callTool(makeServer(skills: nil), name: "generate_skill", arguments: #"{"all":true}"#)
        XCTAssertTrue(result.isError)
    }

    // MARK: - Encoding

    func testResponsesAreSingleLines() async throws {
        let server = makeServer()
        let line = await server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_man_page","arguments":{"tool":"git","limit":4}}}"#)
        let output = try XCTUnwrap(line)
        XCTAssertFalse(output.contains("\n"))
        XCTAssertFalse(output.contains("\r"))
    }

    // MARK: - Helpers

    private func makeServer(skills: (any SkillWriting)? = FakeSkills()) -> MCPServer {
        MCPServer(discovery: FakeDiscovery(tools: Fixtures.tools, docs: Fixtures.docs), skills: skills)
    }

    private func respond(_ server: MCPServer, _ line: String) async throws -> [String: Any] {
        let output = await server.handle(line: line)
        return try parse(try XCTUnwrap(output))
    }

    private func parse(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func parseArray(_ text: String) throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    }

    private func toolNames(_ response: [String: Any]) throws -> [String] {
        let tools = try XCTUnwrap((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        return tools.compactMap { $0["name"] as? String }
    }

    private func callTool(
        _ server: MCPServer,
        name: String,
        arguments: String = "{}"
    ) async throws -> (text: String, isError: Bool) {
        let line = #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#
        let response = try await respond(server, line)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap((result["content"] as? [[String: Any]])?.first)
        let text = try XCTUnwrap(content["text"] as? String)
        let isError = try XCTUnwrap(result["isError"] as? Bool)
        return (text, isError)
    }
}

// MARK: - Fixtures

private enum Fixtures {
    static let git = InstalledTool(
        name: "git", formula: "git", version: "2.45.0",
        path: "/opt/homebrew/Cellar/git/2.45.0/bin/git", summary: "Distributed version control"
    )
    static let rg = InstalledTool(
        name: "rg", formula: "ripgrep", version: "14.1.0",
        path: "/opt/homebrew/Cellar/ripgrep/14.1.0/bin/rg", summary: "Recursive search"
    )
    static let jq = InstalledTool(
        name: "jq", formula: "jq", version: "1.7.1",
        path: "/opt/homebrew/Cellar/jq/1.7.1/bin/jq", summary: nil
    )
    static let tools = [git, rg, jq]

    static let manText = (0..<10).map { "line \($0)" }.joined(separator: "\n")

    static let gitTree = CommandNode(
        name: "git",
        summary: "Distributed version control",
        usage: ["git [--version] <command>"],
        options: [CommandOption(flags: ["--version"], argument: nil, summary: "Print version")],
        subcommands: [
            CommandNode(
                name: "commit", summary: "Record changes", usage: ["git commit [-m <msg>]"],
                options: [CommandOption(flags: ["-m"], argument: "<msg>", summary: "Commit message")],
                subcommands: []
            ),
            CommandNode(
                name: "remote", summary: "Manage remotes", usage: ["git remote"], options: [],
                subcommands: [
                    CommandNode(name: "add", summary: "Add a remote", usage: ["git remote add <name> <url>"],
                                options: [], subcommands: [])
                ]
            )
        ]
    )

    static let docs: [String: ToolDocumentation] = {
        let epoch = Date(timeIntervalSince1970: 0)
        return [
            "git": ToolDocumentation(tool: git, source: .manPage, rawText: manText, tree: gitTree, generatedAt: epoch),
            "rg": ToolDocumentation(
                tool: rg, source: .helpFlag, rawText: "rg --help",
                tree: CommandNode(name: "rg", summary: "Recursive search", usage: ["rg PATTERN"],
                                  options: [], subcommands: []),
                generatedAt: epoch
            ),
            "jq": ToolDocumentation(
                tool: jq, source: .none, rawText: "",
                tree: CommandNode(name: "jq", summary: nil, usage: [], options: [], subcommands: []),
                generatedAt: epoch
            )
        ]
    }()
}

// MARK: - Fakes

private struct FakeDiscovery: ToolDiscoveryProviding {
    let tools: [InstalledTool]
    let docs: [String: ToolDocumentation]

    func listTools() async throws -> [InstalledTool] {
        tools
    }

    func searchTools(_ query: String, limit: Int) async throws -> [InstalledTool] {
        let needle = query.lowercased()
        let matches = tools.filter { tool in
            needle.isEmpty || [tool.name, tool.formula, tool.summary ?? ""].contains { $0.lowercased().contains(needle) }
        }
        return Array(matches.prefix(limit))
    }

    func documentation(for toolName: String) async throws -> ToolDocumentation {
        guard BrewBarPaths.isSafeComponent(toolName) else { throw ToolDiscoveryError.invalidToolName(toolName) }
        guard let doc = docs[toolName] else { throw ToolDiscoveryError.toolNotFound(toolName) }
        return doc
    }
}

private enum FakeSkillError: Error {
    case writeFailed
}

private actor FakeSkills: SkillWriting {
    private(set) var written: [String] = []
    private let failing: Set<String>

    init(failing: Set<String> = []) {
        self.failing = failing
    }

    func writeSkill(for doc: ToolDocumentation) async throws -> URL {
        if failing.contains(doc.tool.name) { throw FakeSkillError.writeFailed }
        written.append(doc.tool.name)
        return URL(fileURLWithPath: "/fake/skills/\(doc.tool.name)/SKILL.md")
    }
}
