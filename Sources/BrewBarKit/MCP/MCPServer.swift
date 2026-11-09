// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// MCP server over newline-delimited JSON-RPC. Transport-free: `handle(line:)` maps one request line
/// to one response line, so the stdio loop lives in the executable target.
public actor MCPServer {
    static let defaultProtocolVersion = "2025-06-18"
    static let resourceScheme = "brewbar://tool/"

    private let discovery: any ToolDiscoveryProviding
    private let skills: (any SkillWriting)?
    private let serverVersion: String

    public init(discovery: any ToolDiscoveryProviding, skills: (any SkillWriting)?, serverVersion: String = "0.1.0") {
        self.discovery = discovery
        self.skills = skills
        self.serverVersion = serverVersion
    }

    /// One request line in, one response line out. nil for notifications and blank lines.
    public func handle(line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = trimmed.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return JSONRPC.error(id: .null, code: JSONRPC.parseError, message: "Parse error")
        }
        guard case .object = value else {
            return JSONRPC.error(id: .null, code: JSONRPC.invalidRequest, message: "Invalid Request: expected a JSON object")
        }
        guard let request = JSONRPCRequest(value: value) else {
            return value["id"].map {
                JSONRPC.error(id: $0, code: JSONRPC.invalidRequest, message: "Invalid Request: missing method")
            }
        }

        // Notifications are never answered, even when they fail.
        guard let id = request.id, !request.method.hasPrefix("notifications/") else { return nil }

        do {
            let result = try await dispatch(method: request.method, params: request.params)
            return JSONRPC.result(id: id, result)
        } catch let error as JSONRPCError {
            return JSONRPC.error(id: id, code: error.code, message: error.message)
        } catch {
            return JSONRPC.error(id: id, code: JSONRPC.internalError, message: Self.describe(error))
        }
    }

    // MARK: - Dispatch

    private func dispatch(method: String, params: JSONValue?) async throws -> JSONValue {
        switch method {
        case "initialize":
            return initializeResult(params: params)
        case "ping":
            return .object([:])
        case "tools/list":
            return .object(["tools": .array(toolDescriptors())])
        case "tools/call":
            return try await callTool(params: params)
        case "resources/list":
            return try await listResources()
        case "resources/read":
            return try await readResource(params: params)
        default:
            throw JSONRPCError(code: JSONRPC.methodNotFound, message: "Method not found: \(method)")
        }
    }

    private func initializeResult(params: JSONValue?) -> JSONValue {
        let protocolVersion = params?["protocolVersion"]?.stringValue ?? Self.defaultProtocolVersion
        return .object([
            "protocolVersion": .string(protocolVersion),
            "capabilities": .object([
                "tools": .object([:]),
                "resources": .object([:])
            ]),
            "serverInfo": .object([
                "name": .string("brewbar"),
                "version": .string(serverVersion)
            ]),
            "instructions": .string(
                "BrewBar lists the Homebrew CLIs installed on this Mac. Before guessing flags or subcommands, "
                + "call list_tools to find the tool, then get_command_tree or get_man_page to read its real syntax."
            )
        ])
    }

    // MARK: - Tool catalogue

    private func toolDescriptors() -> [JSONValue] {
        var tools: [JSONValue] = [
            Self.toolDescriptor(
                name: "list_tools",
                description: "List installed CLI tools, optionally filtered by a case-insensitive query.",
                properties: [
                    "query": Self.property("string", "Match against tool name, formula and summary."),
                    "limit": Self.property("integer", "Maximum results (default 50, max 500).")
                ],
                required: []
            ),
            Self.toolDescriptor(
                name: "get_command_tree",
                description: "Subcommands and options of an installed tool, parsed from its man page or --help.",
                properties: [
                    "tool": Self.property("string", "Executable name, as returned by list_tools."),
                    "depth": Self.property("integer", "Levels to include: 1 = root options only, 2 = plus direct subcommands (default 2).")
                ],
                required: ["tool"]
            ),
            Self.toolDescriptor(
                name: "get_man_page",
                description: "Plain-text man page (or --help) for an installed tool, sliced by line.",
                properties: [
                    "tool": Self.property("string", "Executable name, as returned by list_tools."),
                    "offset": Self.property("integer", "Zero-based first line (default 0)."),
                    "limit": Self.property("integer", "Number of lines to return (default 400, max 2000).")
                ],
                required: ["tool"]
            )
        ]
        if skills != nil {
            tools.append(Self.toolDescriptor(
                name: "generate_skill",
                description: "Write ~/.brewbar/skills/<tool>/SKILL.md for one tool, or for every installed tool with all: true.",
                properties: [
                    "tool": Self.property("string", "Executable name to write a skill for."),
                    "all": Self.property("boolean", "Write skills for every installed tool.")
                ],
                required: []
            ))
        }
        return tools
    }

    private static func toolDescriptor(
        name: String,
        description: String,
        properties: [String: JSONValue],
        required: [String]
    ) -> JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required.map { .string($0) })
            ])
        ])
    }

    private static func property(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }

    // MARK: - tools/call

    private func callTool(params: JSONValue?) async throws -> JSONValue {
        guard let name = params?["name"]?.stringValue else {
            throw JSONRPCError.invalidParams("tools/call requires a string 'name'")
        }
        let arguments = params?["arguments"] ?? .object([:])
        guard case .object = arguments else {
            throw JSONRPCError.invalidParams("tools/call 'arguments' must be an object")
        }

        do {
            switch name {
            case "list_tools":
                return Self.toolResult(try await listTools(arguments))
            case "get_command_tree":
                return Self.toolResult(try await commandTree(arguments))
            case "get_man_page":
                return Self.toolResult(try await manPage(arguments))
            case "generate_skill":
                guard let skills else {
                    return Self.toolResult("generate_skill is not enabled on this server.", isError: true)
                }
                return Self.toolResult(try await generateSkill(arguments, skills: skills))
            default:
                return Self.toolResult(Self.unknownToolMessage(name, skillsEnabled: skills != nil), isError: true)
            }
        } catch let error as ToolArgumentError {
            return Self.toolResult(error.message, isError: true)
        } catch {
            return Self.toolResult(Self.describe(error), isError: true)
        }
    }

    private func listTools(_ arguments: JSONValue) async throws -> String {
        let query = arguments["query"]?.stringValue ?? ""
        let limit = min(max(try Self.optionalInt(arguments, "limit") ?? 50, 1), 500)
        let tools = try await discovery.searchTools(query, limit: limit)
        let entries: [JSONValue] = tools.map { tool in
            .object([
                "name": .string(tool.name),
                "formula": .string(tool.formula),
                "version": .string(tool.version),
                "summary": tool.summary.map { .string($0) } ?? .null
            ])
        }
        return JSONValue.array(entries).encodedString(prettyPrinted: true)
    }

    private func commandTree(_ arguments: JSONValue) async throws -> String {
        let name = try Self.requiredString(arguments, "tool")
        let depth = max(try Self.optionalInt(arguments, "depth") ?? 2, 1)
        let doc = try await discovery.documentation(for: name)
        var fields = Self.treeFields(doc.tree, depth: depth)
        fields["source"] = .string(doc.source.rawValue)
        return JSONValue.object(fields).encodedString(prettyPrinted: true)
    }

    private func manPage(_ arguments: JSONValue) async throws -> String {
        let name = try Self.requiredString(arguments, "tool")
        let offset = max(try Self.optionalInt(arguments, "offset") ?? 0, 0)
        let limit = min(max(try Self.optionalInt(arguments, "limit") ?? 400, 1), 2000)
        let doc = try await discovery.documentation(for: name)

        let lines = Self.lines(of: doc.rawText)
        let start = min(offset, lines.count)
        let end = min(start + limit, lines.count)
        let header: String
        if start == end {
            header = "# \(name) (\(doc.source.rawValue)) no lines at offset \(offset); \(lines.count) total"
        } else {
            header = "# \(name) (\(doc.source.rawValue)) lines \(start + 1)-\(end) of \(lines.count)"
        }
        return ([header] + lines[start..<end]).joined(separator: "\n")
    }

    private func generateSkill(_ arguments: JSONValue, skills: any SkillWriting) async throws -> String {
        if arguments["all"]?.boolValue == true {
            return try await generateAllSkills(skills: skills)
        }
        guard let name = arguments["tool"]?.stringValue else {
            throw ToolArgumentError(message: "Provide 'tool' (executable name) or 'all': true")
        }
        let doc = try await discovery.documentation(for: name)
        return try await skills.writeSkill(for: doc).path
    }

    private func generateAllSkills(skills: any SkillWriting) async throws -> String {
        let tools = try await discovery.listTools()
        var written = 0
        var failedCount = 0
        var failures: [JSONValue] = []
        for tool in tools {
            do {
                let doc = try await discovery.documentation(for: tool.name)
                _ = try await skills.writeSkill(for: doc)
                written += 1
            } catch {
                failedCount += 1
                if failures.count < Self.maxReportedFailures {
                    failures.append(.object(["tool": .string(tool.name), "error": .string(Self.describe(error))]))
                }
            }
        }
        return JSONValue.object([
            "written": .number(Double(written)),
            "failed": .number(Double(failedCount)),
            "failures": .array(failures)
        ]).encodedString(prettyPrinted: true)
    }

    private static let maxReportedFailures = 20

    // MARK: - Resources

    private func listResources() async throws -> JSONValue {
        let tools = try await discovery.listTools()
        let resources: [JSONValue] = tools.map { tool in
            .object([
                "uri": .string(Self.resourceScheme + tool.name),
                "name": .string(tool.name),
                "description": .string(tool.summary ?? ""),
                "mimeType": .string("text/plain")
            ])
        }
        return .object(["resources": .array(resources)])
    }

    private func readResource(params: JSONValue?) async throws -> JSONValue {
        guard let uri = params?["uri"]?.stringValue else {
            throw JSONRPCError.invalidParams("resources/read requires a string 'uri'")
        }
        guard uri.hasPrefix(Self.resourceScheme) else {
            throw JSONRPCError.invalidParams("Unknown resource URI: \(uri)")
        }
        let name = String(uri.dropFirst(Self.resourceScheme.count))
        let doc: ToolDocumentation
        do {
            doc = try await discovery.documentation(for: name)
        } catch let error as ToolDiscoveryError {
            throw JSONRPCError.invalidParams(Self.describe(error))
        }
        return .object([
            "contents": .array([
                .object([
                    "uri": .string(uri),
                    "mimeType": .string("text/plain"),
                    "text": .string(doc.rawText)
                ])
            ])
        ])
    }

    // MARK: - Helpers

    private static func toolResult(_ text: String, isError: Bool = false) -> JSONValue {
        .object([
            "content": .array([
                .object(["type": .string("text"), "text": .string(text)])
            ]),
            "isError": .bool(isError)
        ])
    }

    private static func unknownToolMessage(_ name: String, skillsEnabled: Bool) -> String {
        var available = ["list_tools", "get_command_tree", "get_man_page"]
        if skillsEnabled { available.append("generate_skill") }
        return "Unknown tool '\(name)'. Available tools: \(available.joined(separator: ", ")). "
            + "Call list_tools to discover installed CLI names."
    }

    private static func describe(_ error: Error) -> String {
        switch error as? ToolDiscoveryError {
        case .some(.toolNotFound(let name)):
            return "Tool '\(name)' is not an installed Homebrew CLI. Call list_tools to see the available tool names."
        case .some(.invalidToolName(let name)):
            return "Invalid tool name '\(name)'. Use the executable name exactly as returned by list_tools."
        default:
            return String(describing: error)
        }
    }

    private static func requiredString(_ arguments: JSONValue, _ key: String) throws -> String {
        guard let value = arguments[key]?.stringValue, !value.isEmpty else {
            throw ToolArgumentError(message: "Missing required argument '\(key)' (string)")
        }
        return value
    }

    private static func optionalInt(_ arguments: JSONValue, _ key: String) throws -> Int? {
        guard let raw = arguments[key], raw != .null else { return nil }
        guard let value = raw.intValue else {
            throw ToolArgumentError(message: "Argument '\(key)' must be an integer")
        }
        return value
    }

    /// Lines of `text`, without the empty element a trailing newline would add.
    private static func lines(of text: String) -> [String] {
        var parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    /// Keeps nodes down to `depth` levels; depth 1 is the root with no subcommands.
    private static func treeFields(_ node: CommandNode, depth: Int) -> [String: JSONValue] {
        let children: [JSONValue] = depth > 1
            ? node.subcommands.map { .object(treeFields($0, depth: depth - 1)) }
            : []
        return [
            "name": .string(node.name),
            "summary": node.summary.map { .string($0) } ?? .null,
            "usage": .array(node.usage.map { .string($0) }),
            "options": .array(node.options.map { option in
                .object([
                    "flags": .array(option.flags.map { .string($0) }),
                    "argument": option.argument.map { .string($0) } ?? .null,
                    "summary": .string(option.summary)
                ])
            }),
            "subcommands": .array(children)
        ]
    }
}

/// Bad or missing tool arguments. Reported as a tool error, not a JSON-RPC error.
private struct ToolArgumentError: Error {
    let message: String
}
