import SwiftUI
import BrewBarKit

public struct DiscoverView: View {
    @StateObject private var viewModel = DiscoverViewModel()
    @ObservedObject private var catalog = HomebrewCatalogService.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroBanner

                if catalog.isLoading && viewModel.trending.isEmpty {
                    ProgressView("Loading the Homebrew catalog…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else {
                    sectionDivider

                    if !viewModel.newThisWeek.isEmpty {
                        PackageCarouselSection(title: "New This Week", items: viewModel.newThisWeek)
                        sectionDivider
                    }

                    PackageCarouselSection(title: "Trending", items: viewModel.trending)

                    ForEach(viewModel.categories) { category in
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
        .task {
            // Populate installedPackages so card statuses (Install/Installed/
            // Update) are correct on first render, not just after visiting
            // Installed/Updates.
            try? await BrewService.shared.refreshInstalledPackages()
            try? await BrewService.shared.checkForUpdates()
            await viewModel.load()
        }
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.vertical, 20)
    }

    private var heroBanner: some View {
        let heroItems = Array(viewModel.trending.prefix(5))
        
        return Group {
            if heroItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DISCOVER")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.secondary)
                    Text("Find your next essential tool")
                        .font(.largeTitle)
                        .bold()
                    Text(heroSubtitle)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.4)), in: .rect(cornerRadius: 16))
                .padding(.top)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(heroItems) { item in
                            NavigationLink(destination: FormulaDetailView(formula: item)) {
                                HStack(spacing: 24) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("FEATURED")
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.accentColor)
                                        
                                        Text(item.fullTitle ?? item.name)
                                            .font(.largeTitle)
                                            .bold()
                                            .foregroundColor(.primary)
                                        
                                        Text(item.description)
                                            .font(.title3)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    IconView(item: item, size: 120)
                                        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                                }
                                .padding(40)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(
                                    LinearGradient(colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .padding(.horizontal, 24)
                            }
                            .buttonStyle(.plain)
                            .containerRelativeFrame(.horizontal)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollClipDisabled()
                .frame(height: 250)
                .padding(.top)
            }
        }
    }

    private var heroSubtitle: String {
        guard viewModel.totalAvailableCount > 0 else {
            return "Real formulas and casks worth installing, grouped by what you're trying to get done."
        }
        return "\(viewModel.totalAvailableCount.formatted()) formulas and casks available, grouped by what you're trying to get done."
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
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    IconView(item: item, size: 64)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

                    statusBadge
                        .offset(x: 8, y: -8)
                }

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
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1))
            .shadow(color: Color.black.opacity(isHovered ? 0.2 : 0.0), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if let homepage = item.homepage, let url = URL(string: homepage) {
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
                    Task { try? await BrewService.shared.installFormula(item.id, type: item.type) }
                } label: {
                    Label("Install", systemImage: "square.and.arrow.down")
                }
            } else if status == .updateAvailable {
                Button {
                    Task { try? await BrewService.shared.upgradeFormula(item.id, type: item.type) }
                } label: {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                }
            } else {
                Button(role: .destructive) {
                    Task { try? await BrewService.shared.uninstallFormula(item.id, type: item.type) }
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
            }
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
            Button(action: {
                Task {
                    isWorking = true
                    try? await BrewService.shared.installFormula(item.id, type: item.type)
                    isWorking = false
                }
            }) {
                if isWorking {
                    Image(systemName: "arrow.down.circle")
                        .symbolEffect(.bounce, options: .repeating, value: isWorking)
                } else {
                    Text("Install")
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(isWorking)
        case .installed:
            Text("Installed")
                .font(.caption)
                .foregroundColor(.secondary)
        case .updateAvailable:
            Button(action: {
                Task {
                    isWorking = true
                    try? await BrewService.shared.upgradeFormula(item.id, type: item.type)
                    isWorking = false
                }
            }) {
                if isWorking {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .symbolEffect(.rotate, options: .repeating, value: isWorking)
                } else {
                    Text("Update")
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

    public var body: some View {
        List(items) { item in
            NavigationLink(destination: FormulaDetailView(formula: item)) {
                HStack {
                    IconView(item: item, size: 36)
                    VStack(alignment: .leading) {
                        Text(item.fullTitle ?? item.name).font(.headline)
                        Text(item.description).font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(item.type.displayName).font(.caption)
                }
            }
        }
        .navigationTitle(title)
    }
}
