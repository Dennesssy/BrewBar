// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

public struct DiscoverView: View {
    @StateObject private var viewModel = DiscoverViewModel()
    @ObservedObject private var catalog = HomebrewCatalogService.shared
    @ObservedObject private var brewService = BrewService.shared
    @State private var heroSelection: String?

    private let heroTints: [Color] = [.orange, .blue, .purple, .teal, .pink]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if catalog.isLoading && viewModel.trending.isEmpty {
                    ProgressView("Loading the Homebrew catalog…")
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else if viewModel.trending.isEmpty && catalog.totalFormulaCount == 0 {
                    catalogUnavailableState
                } else {
                    if !heroItems.isEmpty {
                        heroBanner
                        sectionDivider
                    }

                    if !viewModel.newThisWeek.isEmpty {
                        PackageCarouselSection(title: "New This Week", items: viewModel.newThisWeek)
                        sectionDivider
                    }

                    if !trendingItems.isEmpty {
                        PackageCarouselSection(title: "Trending", items: trendingItems)
                    }

                    if !viewModel.categories.isEmpty {
                        sectionDivider
                        categoryGrid
                    }

                    ForEach(viewModel.categories.filter { !$0.items.isEmpty }) { category in
                        sectionDivider
                        PackageCarouselSection(title: category.name, items: category.items, category: category)
                    }
                }
            }
            .padding(.horizontal)
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .scrollClipDisabled()
        .navigationTitle("Discover")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await catalog.refresh()
                        await viewModel.load()
                        try? await brewService.refreshInstalledPackages()
                        try? await brewService.checkForUpdates()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(catalog.isLoading)
                .help("Refresh the catalog and package status")
            }
        }
        .task {
            // Populate installedPackages so card statuses (Install/Installed/
            // Update) are correct on first render, not just after visiting
            // Installed/Updates.
            try? await BrewService.shared.refreshInstalledPackages()
            try? await BrewService.shared.checkForUpdates()
            await viewModel.load()
            if heroSelection == nil {
                heroSelection = heroItems.first?.id
            }
        }
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.vertical, 20)
    }

    private var heroItems: [FormulaItem] {
        Array(viewModel.trending.prefix(5))
    }

    private var heroIDs: Set<String> {
        Set(heroItems.map(\.id))
    }

    private var trendingItems: [FormulaItem] {
        viewModel.trending.filter { !heroIDs.contains($0.id) }
    }

    private var currentHeroID: String? {
        heroSelection ?? heroItems.first?.id
    }

    // MARK: - Hero

    private var heroBanner: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(heroItems.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(destination: FormulaDetailView(formula: item)) {
                        heroCard(item: item, index: index)
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal)
                    .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $heroSelection)
        .scrollClipDisabled()
        .frame(height: 264)
        .overlay(alignment: .bottom) {
            heroPageControl
        }
        .padding(.top)
    }

    private func heroCard(item: FormulaItem, index: Int) -> some View {
        let tint = heroTints[index % heroTints.count]

        return HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("FEATURED")
                        .font(.caption.bold())
                        .foregroundStyle(tint)
                    Text(item.type.displayName.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }

                Text(item.fullTitle ?? item.name)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text(item.description)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Image(systemName: "chevron.right.circle.fill")
                        .foregroundStyle(tint)
                    Text(item.type == .cask ? "View app details" : "View formula details")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 16)

            IconView(item: item, size: 148)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                LinearGradient(
                    colors: [tint.opacity(0.28), tint.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.white.opacity(0.10), .clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 420
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    private var heroPageControl: some View {
        HStack(spacing: 6) {
            ForEach(heroItems) { item in
                let isCurrent = item.id == currentHeroID
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        heroSelection = item.id
                    }
                } label: {
                    Capsule()
                        .fill(Color.primary.opacity(isCurrent ? 0.8 : 0.25))
                        .frame(width: isCurrent ? 16 : 6, height: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Featured: \(item.fullTitle ?? item.name)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 12)
    }

    // MARK: - Categories

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Category")
                .font(.title2)
                .bold()

            GlassEffectContainer(spacing: 14) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(viewModel.categories) { category in
                        NavigationLink(destination: PackageListView(title: category.name, items: category.items)) {
                            HStack(spacing: 12) {
                                Image(systemName: category.systemImage)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(tint(for: category))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        tint(for: category).opacity(0.16),
                                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(categorySubtitle(category))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .glassEffect(
                                .regular,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func tint(for category: PackageCategory) -> Color {
        switch category.id {
        case "dev-tools": return .orange
        case "databases": return .blue
        case "apps": return .purple
        case "productivity": return .green
        default: return .accentColor
        }
    }

    private func categorySubtitle(_ category: PackageCategory) -> String {
        switch category.id {
        case "dev-tools": return "Compilers, CLIs, and version control"
        case "databases": return "Servers, clients, and key-value stores"
        case "apps": return "Everyday Mac apps from Homebrew Cask"
        case "productivity": return "Notes, tasks, launchers, and calendars"
        default: return "\(category.items.count) picks"
        }
    }

    // MARK: - Empty / error

    private var catalogUnavailableState: some View {
        Group {
            if catalog.lastError != nil {
                ContentUnavailableView {
                    Label("Couldn’t Load the Catalog", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("BrewBar needs a network connection the first time it builds its catalog. If you’ve used BrewBar before, cached results will appear when you’re back online.")
                } actions: {
                    Button("Try Again") {
                        Task {
                            await catalog.refresh()
                            await viewModel.load()
                        }
                    }
                    .buttonStyle(.glassProminent)
                }
            } else {
                ContentUnavailableView {
                    Label("No Packages Yet", systemImage: "shippingbox")
                } description: {
                    Text("Run Homebrew update from Preferences to discover new formulas and casks.")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}

/// A titled section whose items scroll horizontally with native paging/snap
/// behavior (macOS 14 `.scrollTargetBehavior(.viewAligned)`), mirroring the
/// App Store Discover page's snapping carousels rather than a static grid.
public struct PackageCarouselSection: View {
    let title: String
    let items: [FormulaItem]
    var category: PackageCategory?
    @ObservedObject private var brewService = BrewService.shared

    public init(title: String, items: [FormulaItem], category: PackageCategory? = nil) {
        self.title = title
        self.items = items
        self.category = category
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2)
                    .bold()
                Spacer()
                NavigationLink("See All", destination: PackageListView(title: title, items: items))
                    .font(.subheadline)
            }

            GlassEffectContainer(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(items) { item in
                            DiscoverPackageCardView(item: item, status: status(for: item))
                                .containerRelativeFrame(.horizontal, count: 3, spacing: 16)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
        }
    }

    private func status(for item: FormulaItem) -> PackageInstallStatus {
        if let installed = brewService.installedPackages.first(where: { $0.id == item.id }) {
            return installed.updateAvailable ? .updateAvailable : .installed
        }
        return .notInstalled
    }
}

public enum PackageInstallStatus {
    case notInstalled
    case installed
    case updateAvailable
}

/// App-icon-styled card: a large rounded-square glyph tile (standing in for
/// a real bundled icon, since formulas/casks have no icon assets to fetch),
/// name, description, an installed/update status badge, and an inline action.
public struct DiscoverPackageCardView: View {
    let item: FormulaItem
    let status: PackageInstallStatus
    @State private var isWorking = false
    @State private var isHovered = false

    public var body: some View {
        NavigationLink(destination: FormulaDetailView(formula: item)) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    IconView(item: item, size: 64)
                        .shadow(color: .black.opacity(0.22), radius: 5, y: 3)

                    statusBadge
                        .offset(x: 8, y: -8)
                }

                Text(item.type.displayName.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(item.fullTitle ?? item.name)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(item.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(height: 30, alignment: .top)

                actionButton
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.30 : 0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.18 : 0.0), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if let appURL = AppLauncher.shared.appURL(for: item) {
                Button {
                    AppLauncher.shared.open(appURL)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                Divider()
            }

            if let homepage = item.homepage, let url = WebLink.url(homepage) {
                ShareLink(item: url) {
                    Label("Share Package", systemImage: "square.and.arrow.up")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(homepage, forType: .string)
                } label: {
                    Label("Copy URL", systemImage: "link")
                }
                Divider()
            }

            if status == .notInstalled {
                Button {
                    Task { await install() }
                } label: {
                    Label("Install", systemImage: "square.and.arrow.down")
                }
            } else if status == .updateAvailable {
                Button {
                    Task { await upgrade() }
                } label: {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                }
            } else {
                Button(role: .destructive) {
                    Task {
                        do {
                            try await BrewService.shared.uninstallFormula(item.id, type: item.type)
                            AppLauncher.shared.rescan()
                        } catch {
                            BrewService.shared.report(error)
                        }
                    }
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
            }
        }
    }

    private func install() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await BrewService.shared.installFormula(item.id, type: item.type)
            AppLauncher.shared.rescan()
        } catch {
            BrewService.shared.report(error)
        }
    }

    private func upgrade() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await BrewService.shared.upgradeFormula(item.id, type: item.type)
            AppLauncher.shared.rescan()
        } catch {
            BrewService.shared.report(error)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .notInstalled:
            EmptyView()
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white, .green)
                .background(Circle().fill(.background))
                .symbolEffect(.bounce, value: isHovered)
        case .updateAvailable:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(.white, .orange)
                .background(Circle().fill(.background))
                .symbolEffect(.variableColor.cumulative.dimInactiveLayers, isActive: isHovered)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .notInstalled:
            Button {
                Task { await install() }
            } label: {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 60)
                } else {
                    Text("Install")
                        .frame(minWidth: 60)
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .disabled(isWorking)
        case .installed:
            if let appURL = AppLauncher.shared.appURL(for: item) {
                Button {
                    AppLauncher.shared.open(appURL)
                } label: {
                    Text("Open")
                        .frame(minWidth: 60)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            } else {
                Label("Installed", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(minHeight: 22)
            }
        case .updateAvailable:
            Button {
                Task { await upgrade() }
            } label: {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 60)
                } else {
                    Text("Update")
                        .frame(minWidth: 60)
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .disabled(isWorking)
        }
    }
}

public struct PackageListView: View {
    let title: String
    let items: [FormulaItem]
    @ObservedObject private var brewService = BrewService.shared

    public init(title: String, items: [FormulaItem]) {
        self.title = title
        self.items = items
    }

    public var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing Here Yet",
                    systemImage: "shippingbox",
                    description: Text("No packages are available in this section right now.")
                )
            } else {
                List(items) { item in
                    NavigationLink(destination: FormulaDetailView(formula: item)) {
                        HStack(spacing: 12) {
                            IconView(item: item, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.fullTitle ?? item.name)
                                    .font(.headline)
                                Text(item.description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let installed = brewService.installedPackages.first(where: { $0.id == item.id }) {
                                Text(installed.updateAvailable ? "Update" : "Installed")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(installed.updateAvailable ? Color.orange : Color.secondary)
                            }
                            Text(item.type.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}
