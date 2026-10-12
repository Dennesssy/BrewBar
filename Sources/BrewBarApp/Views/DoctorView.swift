// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

public struct DoctorView: View {
    @State private var issues: [DoctorIssue] = []
    @State private var isLoading = false
    @State private var error: String?
    @ObservedObject private var brewService = BrewService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Brew Doctor")
                    .font(.title2)
                    .bold()
                Spacer()
                Button(isLoading ? "Checking…" : "Run Doctor") {
                    Task { await runDoctor() }
                }
                .buttonStyle(.glass)
                .disabled(isLoading || brewService.isRunningDoctor)
            }
            .padding()
            
            if let err = error {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            if isLoading || brewService.isRunningDoctor {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if issues.isEmpty {
                ContentUnavailableView(
                    "System Healthy",
                    systemImage: "checkmark.seal.fill",
                    description: Text("Brew Doctor did not find any issues with your Homebrew installation.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(issues) { issue in
                    DoctorIssueRow(issue: issue)
                }
            }
        }
        .navigationTitle("Doctor")
        .task {
            if issues.isEmpty {
                await runDoctor()
            }
        }
    }
    
    private func runDoctor() async {
        isLoading = true
        error = nil
        do {
            issues = try await brewService.doctor()
        } catch {
            self.error = "Doctor failed: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

private struct DoctorIssueRow: View {
    let issue: DoctorIssue
    @ObservedObject private var brewService = BrewService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(issue.severity == .error ? .red : .yellow)
                Text(issue.summary)
                    .font(.headline)
                Spacer()
            }
            
            if !issue.details.isEmpty {
                Text(issue.details)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let fixCommand = issue.fixCommand, !fixCommand.isEmpty {
                Button("Run Fix (\(fixCommand.joined(separator: " ")))") {
                    Task {
                        await runFix(args: fixCommand)
                    }
                }
                .buttonStyle(.glass)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func runFix(args: [String]) async {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let brewPath = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).executablePath
        
        brewService.activeTaskCommand = ([brewPath] + args).joined(separator: " ")
        brewService.activeTaskConsoleOutput = ""
        brewService.activeTaskMessage = "Running fix..."
        
        do {
            _ = try await ProcessManager().execute(
                executablePath: brewPath,
                arguments: args,
                timeout: 120,
                outputHandler: { out in
                    Task { @MainActor in
                        brewService.activeTaskConsoleOutput += out
                    }
                }
            )
            brewService.activeTaskMessage = nil
        } catch {
            brewService.activeTaskMessage = "Fix failed: \(error.localizedDescription)"
        }
    }
}
