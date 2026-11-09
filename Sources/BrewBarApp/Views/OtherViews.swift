// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

public struct InstalledView: View {
    @StateObject private var viewModel = InstalledViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()

            if viewModel.filteredFormulas.isEmpty {
                emptyState
            } else {
                List(viewModel.filteredFormulas) { item in
                    NavigationLink(destination: FormulaDetailView(formula: item)) {
                        HStack(spacing: 12) {
                            IconView(item: item, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.headline)
                                Text(item.description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let bytes = item.sizeInBytes {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if item.updateAvailable {
                                Text("Update")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                            Text(item.currentVersion)
                                .font(.monospaced(.caption)())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Installed")
        .task {
            await viewModel.refresh()
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search installed packages", text: $viewModel.filterState.searchQuery)
                    .textFieldStyle(.plain)
                if !viewModel.filterState.searchQuery.isEmpty {
                    Button {
                        viewModel.filterState.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: 320)

            Picker("Type", selection: $viewModel.filterState.selectedType) {
                Text("All").tag(PackageType?.none)
                Text("Formulas").tag(PackageType?.some(.formula))
                Text("Casks").tag(PackageType?.some(.cask))
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()

            Toggle("Updates Only", isOn: $viewModel.filterState.onlyUpdates)
                .toggleStyle(.checkbox)
                .fixedSize()

            Spacer()

            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(SortOrderOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .frame(width: 170)
        }
        .padding()
    }

    @ViewBuilder
    private var emptyState: some View {
        if !viewModel.filterState.searchQuery.isEmpty {
            ContentUnavailableView.search(text: viewModel.filterState.searchQuery)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filterState.onlyUpdates {
            ContentUnavailableView(
                "No Updates",
                systemImage: "checkmark.circle",
                description: Text("Every installed package is up to date.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "No Packages Installed",
                systemImage: "shippingbox",
                description: Text("Install formulas and casks from Discover to see them here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

public struct UpdatesView: View {
    @StateObject private var viewModel = UpdatesViewModel()
    @State private var updateAllPreview: String?
    @State private var isPreviewing = false
    @State private var message: String?
    @ObservedObject private var brewService = BrewService.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.lastCheckError {
                ContentUnavailableView {
                    Label("Couldn’t Check for Updates", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Try Again") {
                        Task { await viewModel.checkForUpdates() }
                    }
                    .buttonStyle(.glassProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isChecking && viewModel.availableUpdates.isEmpty {
                ProgressView("Checking for Updates…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.availableUpdates.isEmpty {
                ContentUnavailableView(
                    "You’re All Set",
                    systemImage: "checkmark.circle",
                    description: Text("All installed packages are up to date.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                header
                Divider()

                List(viewModel.availableUpdates) { item in
                    HStack(spacing: 12) {
                        IconView(item: item, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.headline)
                            Text("\(item.currentVersion) → \(item.latestVersion ?? "latest")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Update") {
                            Task { await viewModel.updateItem(item) }
                        }
                        .buttonStyle(.glass)
                    }
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                if let output = updateAllPreview {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        ScrollView {
                            Text(output)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)

                        HStack {
                            Button("Cancel") {
                                updateAllPreview = nil
                            }
                            .buttonStyle(.glass)

                            Button("Confirm Update All") {
                                updateAllPreview = nil
                                Task {
                                    await viewModel.updateAll()
                                    message = viewModel.lastCheckError == nil ? "Packages updated." : nil
                                }
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Updates")
        .task {
            await viewModel.checkForUpdates()
        }
    }

    private var header: some View {
        HStack {
            Text("\(viewModel.availableUpdates.count) Update\(viewModel.availableUpdates.count == 1 ? "" : "s") Available")
                .font(.title2)
                .bold()
            Spacer()
            Button(isPreviewing ? "Checking…" : "Update All") {
                Task {
                    isPreviewing = true
                    defer { isPreviewing = false }
                    do {
                        let preview = try await brewService.dryRunUpgradeAll()
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if preview.isEmpty {
                            updateAllPreview = nil
                            message = "Everything is already up to date."
                        } else {
                            updateAllPreview = preview
                            message = nil
                        }
                    } catch {
                        brewService.report(error)
                    }
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(isPreviewing)
        }
        .padding()
    }
}

public struct PreferencesView: View {
    @StateObject private var viewModel = PreferencesViewModel.shared
    @ObservedObject private var brewService = BrewService.shared
    @ObservedObject private var environment = HomebrewEnvironment.shared

    @State private var cleanupPreview: String?
    @State private var isPreviewingCleanup = false
    @State private var showCleanupConfirmation = false
    @State private var cleanupResult: String?
    @State private var updateError: String?
    @State private var doctorResult: String?
    @State private var isPreviewingAutoremove = false
    @State private var autoremovePreview: String?
    @State private var showAutoremoveConfirmation = false
    @State private var autoremoveResult: String?

    public init() {}

    public var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { viewModel.preferences.launchAtLogin },
                    set: { newValue in
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            viewModel.preferences.launchAtLogin = newValue
                        } catch {
                            viewModel.preferences.launchAtLogin = LaunchAtLogin.isEnabled
                            brewService.report(error)
                        }
                    }
                ))
                Toggle("Show menu bar icon", isOn: $viewModel.preferences.showMenuBarIcon)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Homebrew Executable", text: $viewModel.preferences.homebrewPrefix)
                        Button("Detect") {
                            if let detected = HomebrewPath.locateInstalled() {
                                viewModel.preferences.homebrewPrefix = detected
                            } else {
                                viewModel.preferences.homebrewPrefix = ""
                            }
                        }
                        .buttonStyle(.glass)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: environment.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(environment.isAvailable ? Color.green : Color.orange)
                        Text(environment.isAvailable ? "Homebrew is available." : "Homebrew wasn’t found at this path.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Security") {
                Toggle("Allow vulnerability lookups", isOn: $viewModel.preferences.allowVulnerabilityLookups)
                Text("Sends installed package names/versions to OSV.dev to detect known vulnerabilities.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Privacy") {
                VStack(alignment: .leading, spacing: 4) {
                    Button("Opt-out of Homebrew Analytics") {
                        Task {
                            do {
                                try await BrewService.shared.setAnalytics(enabled: false)
                            } catch {
                                brewService.report(error)
                            }
                        }
                    }
                    Text("Homebrew sends telemetry by default. Clicking this turns it off entirely via `brew analytics off`.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("GitHub Integration") {
                SecureField("GitHub Personal Access Token", text: $viewModel.githubToken)
                    .onSubmit {
                        // Commit on submit, not per keystroke — saving each
                        // character would persist half-typed tokens.
                        viewModel.saveToken(viewModel.githubToken)
                    }
                Text("Adding a token increases the GitHub API rate limit from 60 to 5,000 requests per hour, preventing rich package details from failing to load. This is securely stored in your Keychain. Press Return to save.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Taps") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Enter tap name (e.g., homebrew/cask-versions)", text: $viewModel.newTapName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button("Tap") {
                            Task {
                                do {
                                    try await BrewService.shared.tap(viewModel.newTapName)
                                    viewModel.newTapName = ""
                                    await viewModel.loadTaps()
                                } catch {
                                    brewService.report(error)
                                }
                            }
                        }
                        .buttonStyle(.glass)
                        .disabled(viewModel.newTapName.isEmpty)
                    }
                    
                    List {
                        ForEach(viewModel.taps, id: \.self) { tap in
                            HStack {
                                Text(tap)
                                Spacer()
                                Button("Untap") {
                                    Task {
                                        do {
                                            try await BrewService.shared.untap(tap)
                                            await viewModel.loadTaps()
                                        } catch {
                                            brewService.report(error)
                                        }
                                    }
                                }
                                .buttonStyle(.glassProminent)
                            }
                        }
                    }
                    .frame(height: 120)
                }
            }

            Section("Maintenance") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Update Homebrew")
                        if let last = brewService.lastHomebrewUpdate {
                            Text("Last updated \(last.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Refreshes formula/cask definitions before checking for outdated packages.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button(brewService.isUpdatingHomebrew ? "Updating…" : "Update Now") {
                        Task {
                            do {
                                try await brewService.updateHomebrew()
                                updateError = nil
                            } catch {
                                updateError = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(brewService.isUpdatingHomebrew)
                }
                if let updateError {
                    Text(updateError).font(.caption).foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Clean Up")
                            Text("Removes old versions and cached downloads for installed packages.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(isPreviewingCleanup ? "Checking…" : "Preview") {
                            Task {
                                isPreviewingCleanup = true
                                defer { isPreviewingCleanup = false }
                                do {
                                    cleanupPreview = try await brewService.cleanup(dryRun: true)
                                } catch {
                                    brewService.report(error)
                                }
                            }
                        }
                        .buttonStyle(.glass)
                        .disabled(isPreviewingCleanup || brewService.isCleaningUp)

                        Button(brewService.isCleaningUp ? "Cleaning…" : "Clean Up Now") {
                            showCleanupConfirmation = true
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(brewService.isCleaningUp)
                    }

                    if let cleanupPreview, !cleanupPreview.isEmpty {
                        ScrollView {
                            Text(cleanupPreview)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    }

                    if let cleanupResult, !cleanupResult.isEmpty {
                        Text(cleanupResult)
                            .font(.caption)
                            .foregroundColor(cleanupResult.hasPrefix("Clean up failed") ? .red : .secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Autoremove")
                            Text("Removes installed packages that are no longer needed as dependencies.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(isPreviewingAutoremove ? "Checking…" : "Preview") {
                            Task {
                                isPreviewingAutoremove = true
                                defer { isPreviewingAutoremove = false }
                                do {
                                    autoremovePreview = try await brewService.autoremove(dryRun: true)
                                } catch {
                                    brewService.report(error)
                                }
                            }
                        }
                        .buttonStyle(.glass)
                        .disabled(isPreviewingAutoremove)

                        Button("Autoremove Now") {
                            showAutoremoveConfirmation = true
                        }
                        .buttonStyle(.glassProminent)
                    }

                    if let autoremovePreview, !autoremovePreview.isEmpty {
                        ScrollView {
                            Text(autoremovePreview)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    }

                    if let autoremoveResult, !autoremoveResult.isEmpty {
                        Text(autoremoveResult)
                            .font(.caption)
                            .foregroundColor(autoremoveResult.hasPrefix("Autoremove failed") ? .red : .secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Brew Doctor")
                            Text("Checks your system for potential Homebrew problems. See the Doctor tab for more details.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Preferences")
        .task {
            viewModel.preferences.launchAtLogin = LaunchAtLogin.isEnabled
            await environment.refresh()
            await viewModel.loadTaps()
        }
        .onChange(of: viewModel.preferences) { _, _ in
            viewModel.save()
        }
        .onChange(of: viewModel.preferences.homebrewPrefix) { _, newValue in
            Task { await environment.setPath(newValue) }
        }
        .alert("Clean Up Homebrew?", isPresented: $showCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clean Up", role: .destructive) {
                Task {
                    do {
                        let output = try await brewService.cleanup(dryRun: false)
                        cleanupResult = output.isEmpty ? "Nothing to clean up." : output
                        cleanupPreview = nil
                    } catch {
                        // Preserve the preview on failure — a failed cleanup
                        // (bad path, timeout) is not the same as "nothing to
                        // clean up" and shouldn't look like a success.
                        cleanupResult = "Clean up failed: \(error.localizedDescription)"
                    }
                }
            }
        } message: {
            Text("This permanently deletes old versions and cached downloads for installed formulas and casks. This cannot be undone.")
        }
        .alert("Autoremove Packages?", isPresented: $showAutoremoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Autoremove", role: .destructive) {
                Task {
                    do {
                        let output = try await brewService.autoremove(dryRun: false)
                        autoremoveResult = output.isEmpty ? "Nothing to autoremove." : output
                        autoremovePreview = nil
                    } catch {
                        autoremoveResult = "Autoremove failed: \(error.localizedDescription)"
                    }
                }
            }
        } message: {
            Text("This permanently removes installed packages that are no longer needed as dependencies. This cannot be undone.")
        }
    }
}
