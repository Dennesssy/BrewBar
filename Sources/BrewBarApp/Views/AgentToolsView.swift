// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import AppKit
import BrewBarKit

/// Owns skill generation so a long run survives tab switches and stays cancellable.
@MainActor
final class SkillGenerationModel: ObservableObject {
    static let shared = SkillGenerationModel()

    @Published private(set) var isRunning = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var failures = 0
    @Published private(set) var statusMessage: String?

    private var task: Task<Void, Never>?

    /// No-op while a run is already in progress, so runs never overlap.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        done = 0
        total = 0
        failures = 0
        statusMessage = nil
        task = Task {
            defer {
                isRunning = false
                task = nil
            }
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

    func cancel() {
        task?.cancel()
    }

    func reportError(_ message: String) {
        statusMessage = message
    }
}

/// Setup for terminal agents that read installed Homebrew CLIs through brewbar-mcp.
struct AgentToolsView: View {
    @ObservedObject private var generator = SkillGenerationModel.shared
    @State private var toolCountLabel = "loading..."
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

                    if generator.isRunning {
                        ProgressView(value: Double(generator.done), total: Double(max(generator.total, 1)))
                        Text("\(generator.done) of \(generator.total) processed, \(generator.failures) failed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let status = generator.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        if generator.isRunning {
                            Button("Cancel", role: .cancel) {
                                generator.cancel()
                            }
                        } else {
                            Button("Generate Skills") {
                                generator.start()
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

    private func openSkillsFolder() {
        let folder = BrewBarPaths.skills
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch {
            generator.reportError("Could not create skills folder: \(error.localizedDescription)")
        }
    }
}
