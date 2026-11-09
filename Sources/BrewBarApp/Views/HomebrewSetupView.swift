// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import AppKit
import BrewBarKit

/// First-run screen shown when Homebrew itself is missing or the configured
/// executable moved. Lets the user adopt an existing install or point BrewBar
/// at one, instead of leaving every action to fail with a shell error.
public struct HomebrewSetupView: View {
    @ObservedObject private var environment = HomebrewEnvironment.shared

    @State private var isWorking = false
    @State private var errorMessage: String?

    public init() {}

    private var detectedPath: String? {
        if case .missing(let path) = environment.status { return path }
        return nil
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.orange.opacity(0.85), .yellow.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)

                    Image(systemName: "mug.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

                Text("Homebrew Is Required")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("BrewBar is a native front end for Homebrew. Install Homebrew, then come back — or point BrewBar at an existing install.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)

                if let detectedPath {
                    VStack(spacing: 10) {
                        Text("Homebrew was found at:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(detectedPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                        Button("Use This Homebrew") {
                            adopt(detectedPath)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(isWorking)
                    }
                    .padding(.top, 4)
                }

                HStack(spacing: 10) {
                    if detectedPath == nil {
                        Button {
                            openInstallPage()
                        } label: {
                            Label("Install Homebrew", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.glassProminent)
                    } else {
                        Button {
                            openInstallPage()
                        } label: {
                            Label("Install Homebrew", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.glass)
                    }

                    Button {
                        chooseExecutable()
                    } label: {
                        Label("Choose Homebrew…", systemImage: "folder")
                    }
                    .buttonStyle(.glass)
                    .disabled(isWorking)
                }
                .controlSize(.large)

                if isWorking || environment.status == .checking {
                    ProgressView("Checking Homebrew…")
                        .controlSize(.small)
                        .padding(.top, 4)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                Text("After installing, open a new terminal and follow the installer’s instructions. BrewBar looks in /opt/homebrew and /usr/local by default.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await environment.refresh()
        }
    }

    private func openInstallPage() {
        guard let url = URL(string: "https://brew.sh") else { return }
        NSWorkspace.shared.open(url)
    }

    private func adopt(_ path: String) {
        isWorking = true
        errorMessage = nil
        Task {
            await environment.setPath(path)
            isWorking = false
            if environment.isAvailable {
                await refreshPackageState()
            } else {
                errorMessage = "That Homebrew executable couldn’t be run. Check the path and try again."
            }
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        panel.prompt = "Use Homebrew"
        panel.message = "Choose the brew executable (usually /opt/homebrew/bin/brew)."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        adopt(url.path)
    }

    private func refreshPackageState() async {
        try? await BrewService.shared.refreshInstalledPackages()
        try? await BrewService.shared.checkForUpdates()
        await HomebrewCatalogService.shared.refresh()
    }
}
