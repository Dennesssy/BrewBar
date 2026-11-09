// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import AppKit
import BrewBarKit

/// App Store-style product page: icon + title + primary action, a metadata
/// strip, a readable description, and related packages.
public struct FormulaDetailView: View {
    @StateObject private var viewModel: FormulaDetailViewModel
    @ObservedObject private var brewService = BrewService.shared
    @ObservedObject private var catalog = HomebrewCatalogService.shared

    @State private var isWorking = false
    @State private var showUninstallConfirmation = false
    @State private var showFullReadme = false
    @State private var showManual = false
    @State private var launchTarget: URL?
    @State private var copiedCommand = false

    public init(formula: FormulaItem) {
        _viewModel = StateObject(wrappedValue: FormulaDetailViewModel(formula: formula))
    }

    private var formula: FormulaItem { viewModel.formula }
    private var installedItem: FormulaItem? {
        brewService.installedPackages.first { $0.id == formula.id }
    }
    private var isInstalled: Bool { installedItem != nil }
    private var needsUpdate: Bool { installedItem?.updateAvailable ?? formula.updateAvailable }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                infoStrip
                aboutSection
                manualSection
                dependenciesSection
                relatedSection
                footerLinks
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(formula.name)
        .task {
            viewModel.fetchRichDetailsIfNeeded()
            launchTarget = AppLauncher.shared.appURL(for: formula)
            if !catalog.hasLoaded {
                await catalog.loadIfNeeded()
            }
        }
        .alert("Uninstall \(formula.name)?", isPresented: $showUninstallConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                Task { await uninstall() }
            }
        } message: {
            Text("This removes the package from your Mac. You can reinstall it from Discover at any time.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            IconView(item: formula, size: 104)
                .shadow(color: .black.opacity(0.20), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(formula.type.displayName.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    if installedItem?.isPinned == true {
                        Label("Pinned", systemImage: "pin.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                Text(formula.fullTitle ?? formula.name)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .lineLimit(2)

                Text(formula.description.isEmpty ? "No description provided." : formula.description)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let publisher = viewModel.githubPublisher {
                    Label(publisher, systemImage: "person.crop.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 10) {
                primaryAction
                HStack(spacing: 8) {
                    shareButton
                    moreMenu
                }
            }
            .frame(minWidth: 150, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if formula.isRemoteSuggestion {
            if let repository = formula.repository, let url = WebLink.url(repository) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text("View on GitHub")
                        .frame(minWidth: 92)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        } else if needsUpdate {
            actionButton("Update", systemImage: "arrow.triangle.2.circlepath") {
                await upgrade()
            }
        } else if isInstalled {
            if let launchTarget {
                Button {
                    AppLauncher.shared.open(launchTarget)
                } label: {
                    Text("Open")
                        .frame(minWidth: 92)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            } else {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.quaternary, in: Capsule())
            }
        } else {
            actionButton("Install", systemImage: "arrow.down.circle") {
                await install()
            }
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            guard !isWorking else { return }
            Task {
                isWorking = true
                defer { isWorking = false }
                await action()
            }
        } label: {
            HStack(spacing: 6) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(isWorking ? "Working…" : title)
            }
            .frame(minWidth: 92)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(isWorking || brewService.activeTaskMessage != nil)
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shareURL {
            ShareLink(item: shareURL) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .help("Share \(formula.name)")
        }
    }

    private var moreMenu: some View {
        Menu {
            if isInstalled {
                Button(installedItem?.isPinned == true ? "Unpin" : "Pin") {
                    Task { await togglePin() }
                }
                Button("Uninstall…", role: .destructive) {
                    showUninstallConfirmation = true
                }
                Divider()
            }

            Button {
                copyInstallCommand()
            } label: {
                Label(copiedCommand ? "Copied!" : "Copy Install Command",
                      systemImage: copiedCommand ? "checkmark" : "doc.on.doc")
            }

            if let homepageURL {
                Link(destination: homepageURL) {
                    Label("Open Homepage", systemImage: "safari")
                }
            }
            if let brewPageURL {
                Link(destination: brewPageURL) {
                    Label("View on formulae.brew.sh", systemImage: "globe")
                }
            }
            if let repositoryURL {
                Link(destination: repositoryURL) {
                    Label("View Source", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .controlSize(.large)
        .help("More actions")
    }

    // MARK: - Metadata

    private var infoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 28) {
                ForEach(Array(infoColumns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(column.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(column.value)
                            .font(.headline)
                    }
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .quaternary,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var infoColumns: [(label: String, value: String)] {
        var columns: [(String, String)] = [
            ("VERSION", displayVersion),
            ("CATEGORY", formula.type.displayName)
        ]

        if let size = installedItem?.sizeInBytes ?? formula.sizeInBytes {
            columns.append(("SIZE", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
        }
        if let license = formula.license, !license.isEmpty {
            columns.append(("LICENSE", license))
        }
        if let publisher = viewModel.githubPublisher {
            columns.append(("DEVELOPER", publisher))
        }
        if let updated = viewModel.githubLastUpdated {
            columns.append(("UPDATED", updated.formatted(date: .abbreviated, time: .omitted)))
        }
        return columns
    }

    private var displayVersion: String {
        if needsUpdate,
           let latest = installedItem?.latestVersion ?? formula.latestVersion,
           !latest.isEmpty {
            return latest
        }
        let version = installedItem?.currentVersion ?? formula.currentVersion
        return version.isEmpty ? "—" : version
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About")
                .font(.title2)
                .bold()

            Text(formula.description.isEmpty ? "No description provided." : formula.description)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if let displayedReadme {
                Text(displayedReadme)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.top, 4)

                if readmeCanExpand && !showFullReadme {
                    Button("Read More") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFullReadme = true
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            } else if viewModel.isFetchingDetails {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
    }

    private var fullReadmeText: String? {
        guard let readme = viewModel.githubReadme else { return nil }
        let text = ReadmeFormatter.plainText(from: readme, limit: 20_000)
        return text.isEmpty ? nil : text
    }

    private var displayedReadme: String? {
        guard let fullReadmeText else { return nil }
        guard !showFullReadme, fullReadmeText.count > 2_500 else { return fullReadmeText }
        return String(fullReadmeText.prefix(2_500)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private var readmeCanExpand: Bool {
        (fullReadmeText?.count ?? 0) > 2_500
    }

    // MARK: - Manual, dependencies, related

    @ViewBuilder
    private var manualSection: some View {
        if let manPage = viewModel.manPage, !manPage.isEmpty {
            Divider()
            DisclosureGroup(isExpanded: $showManual) {
                ScrollView {
                    Text(manPage)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(height: 260)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .padding(.top, 8)
            } label: {
                Label("Manual & Help", systemImage: "book")
                    .font(.title3.bold())
            }
        }
    }

    @ViewBuilder
    private var dependenciesSection: some View {
        if !formula.dependencies.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Dependencies")
                    .font(.title2)
                    .bold()

                ForEach(formula.dependencies) { dependency in
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox")
                            .foregroundStyle(.secondary)
                        Text(dependency.name)
                        if dependency.isOptional {
                            Text("optional")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var relatedSection: some View {
        if !relatedItems.isEmpty {
            Divider()
            PackageCarouselSection(title: "You Might Also Like", items: relatedItems)
        }
    }

    private var relatedItems: [FormulaItem] {
        let pool = formula.type == .cask
            ? catalog.topCasks(limit: 14)
            : catalog.topFormulas(limit: 14)
        return pool
            .filter { $0.id != formula.id }
            .prefix(6)
            .map { $0 }
    }

    @ViewBuilder
    private var footerLinks: some View {
        Divider()
        HStack(spacing: 18) {
            if let homepageURL {
                Link("Developer Website", destination: homepageURL)
            }
            if let brewPageURL {
                Link("Homebrew Page", destination: brewPageURL)
            }
            if let repositoryURL {
                Link("Source Code", destination: repositoryURL)
            }
            Spacer()
            if let installedDate = installedItem?.installedDate {
                Text("Installed \(installedDate.formatted(date: .abbreviated, time: .omitted))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    // MARK: - Derived URLs

    private var shareURL: URL? {
        if let homepage = formula.homepage, let url = WebLink.url(homepage) {
            return url
        }
        return brewPageURL
    }

    private var homepageURL: URL? {
        WebLink.url(formula.homepage)
    }

    private var repositoryURL: URL? {
        WebLink.url(formula.repository)
    }

    private var brewPageURL: URL? {
        let kind = formula.type == .cask ? "cask" : "formula"
        return URL(string: "https://formulae.brew.sh/\(kind)/\(formula.id)")
    }

    // MARK: - Actions

    private func install() async {
        do {
            try await brewService.installFormula(formula.id, type: formula.type)
            AppLauncher.shared.rescan()
            launchTarget = AppLauncher.shared.appURL(for: formula)
        } catch {
            brewService.report(error)
        }
    }

    private func upgrade() async {
        do {
            try await brewService.upgradeFormula(formula.id, type: formula.type)
            AppLauncher.shared.rescan()
            launchTarget = AppLauncher.shared.appURL(for: formula)
        } catch {
            brewService.report(error)
        }
    }

    private func uninstall() async {
        do {
            try await brewService.uninstallFormula(formula.id, type: formula.type)
            launchTarget = nil
        } catch {
            brewService.report(error)
        }
    }

    private func togglePin() async {
        do {
            if installedItem?.isPinned == true {
                try await brewService.unpinFormula(formula.name)
            } else {
                try await brewService.pinFormula(formula.name)
            }
        } catch {
            brewService.report(error)
        }
    }

    private func copyInstallCommand() {
        let command = formula.type == .cask
            ? "brew install --cask \(formula.id)"
            : "brew install \(formula.id)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedCommand = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedCommand = false
        }
    }
}
