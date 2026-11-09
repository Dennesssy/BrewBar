# BrewBar MCP — Local Tool Discovery for Terminal Agents

Turn every Homebrew-installed CLI into a queryable man page / command tree,
exposed to local terminal agents (Claude Code, Codex, opencode, aider…) over
MCP stdio, with optional generated skills in `~/.brewbar/skills`.

## Topology

```
 ┌──────────────────────┐   spawns (stdio)    ┌───────────────────────────────┐
 │ Terminal agent       │ ──────────────────▶ │ brewbar-mcp  (BrewBarMCP)     │
 │ claude / codex / …   │ ◀── JSON-RPC 2.0 ── │  main.swift: read stdin lines │
 └──────────────────────┘  newline-delimited  │  → MCPServer.handle(line)     │
        ▲  stdout = protocol ONLY             │  → write one line to stdout   │
        │  stderr = Logger (fixed)            └──────────────┬────────────────┘
        │                                                    │ BrewBarKit
        │ reads SKILL.md                                     ▼
 ┌──────┴───────────────┐            ┌──────────────────────────────────────┐
 │ ~/.brewbar/          │◀── writes ─│ ToolDiscoveryService (actor)         │
 │  skills/<tool>/      │            │  ├ InstalledToolCatalog              │
 │    SKILL.md          │            │  │   brew info --installed --json=v2 │
 │  cache/docs/         │◀── r/w ────│  │   + scan <Cellar>/<f>/<v>/bin/*   │
 │    <tool>.json       │            │  ├ CommandTreeExtractor              │
 └──────────────────────┘            │  │   man -P cat <tool> | stripOver.. │
        ▲                            │  │   else <keg>/bin/<tool> --help    │
        │ "Generate skills" button   │  │   → CommandNode tree              │
 ┌──────┴───────────────┐            │  └ SkillGenerator → SKILL.md         │
 │ BrewBar.app          │── uses ───▶└──────────────────────────────────────┘
 │  AgentToolsView      │   same Kit
 └──────────────────────┘
```

Security notes (inline):
- **Read-only.** No MCP tool installs, upgrades, or runs arbitrary commands.
  The only process spawned per tool is `man` or `<keg path> --help`, both with
  stdin = /dev/null (ProcessManager fix), 10 s timeout, no shell.
- `--help` runs only binaries whose resolved path is inside the Homebrew
  Cellar — never arbitrary `$PATH` lookups or agent-supplied paths.
- `--help` runs under `sandbox-exec` with **all file writes and network
  denied**. Not every binary honors `--help` — an unsandboxed sweep of 1,840
  binaries left keygen output (`rsa_priv.txt`), dictionaries and temp files
  in the cwd. Sandboxed sweep: 0 stray files. `BREWBAR_HOME` relocates
  `~/.brewbar` for tests.
- Tool names from agents are validated with `BrewBarPaths.isSafeComponent`
  before use as an argv element or directory name (no `..`, `/`, leading `.`).
- Writes confined to `~/.brewbar/`. Skills are generated only on explicit
  request (`generate_skill` tool or app button), never on read paths.

## MCP surface (protocol 2025-06-18, stdio)

| Method / tool              | Input                         | Output                                   |
|----------------------------|-------------------------------|------------------------------------------|
| `initialize`               | client caps                   | `{tools:{}, resources:{}}`, serverInfo   |
| tool `list_tools`          | `query?`, `limit?` (50)       | `[InstalledTool]` name/formula/summary   |
| tool `get_command_tree`    | `tool`, `depth?` (2)          | `CommandNode` JSON, pruned to depth      |
| tool `get_man_page`        | `tool`, `offset?`, `limit?`   | plain text slice (default 400 lines)     |
| tool `generate_skill`      | `tool` or `all: true`         | written paths under ~/.brewbar/skills    |
| `resources/list`           | —                             | `brewbar://tool/<name>` per tool         |
| `resources/read`           | `uri`                         | rendered man/help text                   |

Errors: unknown tool → tool result `isError: true` with message (not a
JSON-RPC error); malformed JSON → `-32700`; unknown method → `-32601`.

## Constraints

| Item              | Value                                                      |
|-------------------|------------------------------------------------------------|
| Platform          | macOS 26, Swift 6.2, SwiftPM — no third-party deps         |
| Transport         | stdio, one JSON object per line, UTF-8                     |
| Response size     | man text sliced; tree pruned by `depth`; list capped       |
| Cache key         | `<tool>.json` invalidated when `InstalledTool.version` changes |
| Per-tool timeout  | 10 s for man/--help                                        |
| Full sweep        | 1,840 binaries ≈ 7 min cold (668 man, 1,144 --help, 28 none); cached after |

## Files

```
Sources/BrewBarKit/ToolDiscovery/
  ToolDiscoveryModels.swift   contract: InstalledTool, CommandNode, protocol, BrewBarPaths
  ManPageText.swift           overstrike stripping (shared with Details view)
  InstalledToolCatalog.swift  formula → binaries
  CommandTreeExtractor.swift  text → CommandNode
  ToolDiscoveryService.swift  actor; cache; implements ToolDiscoveryProviding
  SkillGenerator.swift        CommandNode → SKILL.md
Sources/BrewBarKit/MCP/
  JSONRPC.swift               request/response/error types
  MCPServer.swift             dispatch; takes any ToolDiscoveryProviding
Sources/BrewBarMCP/main.swift stdin loop
Sources/BrewBarApp/Views/AgentToolsView.swift   setup snippet + generate skills
```

## Client setup

```
swift build -c release --product brewbar-mcp
claude mcp add brewbar -- "$(pwd)/.build/release/brewbar-mcp"
```

## Roadmap

- v0.1  catalog + tree + MCP stdio + skills (this milestone)
- v0.2  casks' CLI shims (`/Applications/*.app/Contents/.../bin`), zsh completion parsing as a 3rd doc source
- v0.3  FSEvents on Cellar → proactive cache refresh; `tools/list_changed` notifications
