import SwiftUI
import BrewBarKit

public struct DiscoverView: View {
    @StateObject private var viewModel = DiscoverViewModel()
    @State private var searchText = ""
    @EnvironmentObject private var searchState: AppSearchState
    @Binding var selectedTab: ContentView.Tab

    init(selectedTab: Binding<ContentView.Tab>) {
        _selectedTab = selectedTab
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchField

                heroBanner
                    .padding(.top, 20)

                sectionDivider

                PackageCarouselSection(title: "Editor's Picks", items: viewModel.editorsPicks)

                ForEach(viewModel.categories) { category in
                    sectionDivider
                    PackageCarouselSection(title: category.name, items: category.items, category: category)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("Discover")
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search formulas & casks...", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    searchState.pendingQuery = searchText
                    selectedTab = .search
                }
        }
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
        .padding(.top, 12)
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.vertical, 20)
    }

    private var heroBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISCOVER")
                .font(.caption)
                .bold()
                .foregroundColor(.secondary)
            Text("Find your next essential tool")
                .font(.largeTitle)
                .bold()
            Text("Curated formulas and casks worth installing, grouped by what you're trying to get done.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .glassEffect(.regular.tint(Color.accentColor.opacity(0.4)), in: .rect(cornerRadius: 16))
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

    public var body: some View {
        NavigationLink(destination: FormulaDetailView(formula: item)) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: item.type == .cask ? "desktopcomputer" : "terminal")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        )
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
        }
        .buttonStyle(.plain)
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
        case .updateAvailable:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(.white, .orange)
                .background(Circle().fill(.background))
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .notInstalled:
            Button(isWorking ? "…" : "Install") {
                Task {
                    isWorking = true
                    try? await BrewService.shared.installFormula(item.id)
                    isWorking = false
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
            Button(isWorking ? "…" : "Update") {
                Task {
                    isWorking = true
                    try? await BrewService.shared.upgradeFormula(item.id)
                    isWorking = false
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
                    Image(systemName: item.type == .cask ? "desktopcomputer" : "terminal")
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
