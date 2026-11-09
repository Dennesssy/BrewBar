// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation
import BrewBarKit

// brewbar-mcp: MCP stdio server. One JSON-RPC message per line on stdin,
// one response per line on stdout. Logs go to stderr (see Logger).

let brewPath = ProcessInfo.processInfo.environment["BREWBAR_BREW_PATH"] ?? HomebrewPath.defaultBrewExecutable
let server = MCPServer(
    discovery: ToolDiscoveryService(brewPath: brewPath),
    skills: SkillGenerator()
)

while let line = readLine(strippingNewline: true) {
    guard let response = await server.handle(line: line) else { continue }
    FileHandle.standardOutput.write(Data((response + "\n").utf8))
}
