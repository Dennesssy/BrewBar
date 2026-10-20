// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import AppKit
import BrewBarKit

/// Setup for terminal agents that read installed Homebrew CLIs through brewbar-mcp.
struct AgentToolsView: View {
    @State private var toolCountLabel = "loading..."
    @State private var generationTask: Task<Void, Never>?
    @State private var done = 0
    @State private var total = 0
    @State private var failures = 0
    @State private var statusMessage: String?
    @State private var copied = false

    private var serverPath: String? {
        guard let dir = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let path = dir.appendingPathComponent("brewbar-mcp").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private var setupCommand: String {
        if let serverPath {
            return "claude mcp add brewbar -- \"\(serverPath)\""
        }
        return "swift build -c release --product brewbar-mcp"
    }

    private var isGenerating: Bool { generationTask != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Agent Tools")
                .font(.title2)
                .bold()

            Text("BrewBar can expose installed Homebrew CLIs to local terminal agents over MCP.")
                .foregroundColor(.secondary)

            GroupBox("Server") {
                VStack(alignment: .leading, spacing: 8) {
                    if let serverPath {
                        Text(serverPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("brewbar-mcp was not found next to this app. Build it from the repository:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(setupCommand)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(setupCommand, forType: .string)
                            copied = true
                        }
                        .buttonStyle(.glass)
                    }

                    Text("Installed tools: \(toolCountLabel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Skills") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Writes one SKILL.md per installed tool to ~/.brewbar/skills. A full run takes about 7 minutes for roughly 1,800 tools.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if isGenerating {
                        ProgressView(value: Double(done), total: Double(max(total, 1)))
                        Text("\(done) of \(total) processed, \(failures) failed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        if isGenerating {
                            Button("Cancel", role: .cancel) {
                                generationTask?.cancel()
                            }
                        } else {
                            Button("Generate Skills") {
                                startGeneration()
                            }
                            .buttonStyle(.glassProminent)
                        }
                        Button("Open Skills Folder") {
                            openSkillsFolder()
                        }
                        .buttonStyle(.glass)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Agent Tools")
        .task {
            await loadToolCount()
        }
    }

    private func loadToolCount() async {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let service = ToolDiscoveryService(brewPath: prefs.homebrewPrefix)
        do {
            toolCountLabel = String(try await service.listTools().count)
        } catch {
            toolCountLabel = "unavailable"
        }
    }

    private func startGeneration() {
        guard generationTask == nil else { return }
        done = 0
        total = 0
        failures = 0
        statusMessage = nil
        generationTask = Task {
            defer { generationTask = nil }
            let prefs = await LocalStorageManager.shared.loadPreferences()
            let service = ToolDiscoveryService(brewPath: prefs.homebrewPrefix)
            let writer = SkillGenerator()
            do {
                let tools = try await service.listTools()
                total = tools.count
                for tool in tools {
                    if Task.isCancelled { break }
                    do {
                        let doc = try await service.documentation(for: tool.name)
                        _ = try await writer.writeSkill(for: doc)
                    } catch {
                        failures += 1
                    }
                    done += 1
                }
                if Task.isCancelled {
                    statusMessage = "Cancelled after \(done) of \(total) tools. The index was not rewritten."
                    return
                }
                _ = try writer.writeIndex(tools: tools)
                statusMessage = "Finished: \(done - failures) skills written, \(failures) failed."
            } catch {
                statusMessage = "Generation failed: \(error.localizedDescription)"
            }
        }
    }

    private func openSkillsFolder() {
        let folder = BrewBarPaths.skills
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch {
            statusMessage = "Could not create skills folder: \(error.localizedDescription)"
        }
    }
}
