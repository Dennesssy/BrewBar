// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

public struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @ObservedObject private var searchService = SearchService.shared
    @ObservedObject private var brewService = BrewService.shared
    @EnvironmentObject private var searchState: AppSearchState

    private let suggestions = ["git", "node", "python", "docker", "chrome", "firefox"]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
        }
        .navigationTitle("Search")
        .onChange(of: viewModel.query) { _, _ in
            viewModel.scheduleSearch()
        }
        .onChange(of: viewModel.filterState.selectedType) { _, _ in
            guard viewModel.hasSearched else { return }
            Task { await viewModel.performSearch() }
        }
        .onChange(of: searchState.pendingQuery) { _, newValue in
            runSearch(newValue)
        }
        .task {
            runSearch(searchState.pendingQuery)
        }
    }

    private func runSearch(_ query: String) {
        guard !query.isEmpty else { return }
        viewModel.query = query
        searchState.pendingQuery = ""
        Task { await viewModel.performSearch() }
    }

    // MARK: - Search field

    private var searchField: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                TextField("Search formulas & casks", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit {
                        Task { await viewModel.performSearch() }
                    }

                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }

                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Picker("Type", selection: $viewModel.filterState.selectedType) {
                Text("All").tag(PackageType?.none)
                Text("Formulas").tag(PackageType?.some(.formula))
                Text("Casks").tag(PackageType?.some(.cask))
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasSearched {
            recentSearches
        } else if viewModel.results.isEmpty {
            if viewModel.isSearching {
                ProgressView("Searching Homebrew…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView.search(text: viewModel.query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        List {
            Section {
                ForEach(viewModel.results) { item in
                    SearchResultRow(item: item)
                }
            } header: {
                Text(viewModel.results.count == 1 ? "1 Result" : "\(viewModel.results.count) Results")
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Recent & suggested searches

    private var recentSearches: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !searchService.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Recent Searches")
                                .font(.title3)
                                .bold()
                            Spacer()
                            Button("Clear") {
                                searchService.clearRecentSearches()
                            }
                            .buttonStyle(.link)
                            .font(.subheadline)
                        }

                        VStack(spacing: 0) {
                            ForEach(searchService.recentSearches, id: \.self) { query in
                                Button {
                                    viewModel.query = query
                                    Task { await viewModel.performSearch() }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(.secondary)
                                        Text(query)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "arrow.up.left")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if query != searchService.recentSearches.last {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggested Searches")
                        .font(.title3)
                        .bold()

                    FlowLayout(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                viewModel.query = suggestion
                                Task { await viewModel.performSearch() }
                            } label: {
                                Text(suggestion)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A single App Store-style search result: icon, name, and description link to
/// the detail page; the trailing control mirrors the Get/Update/Open action.
private struct SearchResultRow: View {
    let item: FormulaItem

    @ObservedObject private var brewService = BrewService.shared
    @State private var isWorking = false

    private var installed: FormulaItem? {
        brewService.installedPackages.first { $0.id == item.id }
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: FormulaDetailView(formula: item)) {
                HStack(spacing: 12) {
                    IconView(item: item, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.fullTitle ?? item.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(item.type.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(item.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            actionControl
                .frame(minWidth: 74)
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let homepage = item.homepage, let url = WebLink.url(homepage) {
                Link("Open Homepage", destination: url)
                Button("Copy Homepage URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(homepage, forType: .string)
                }
            }
            Button("Copy Install Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "brew \(item.type == .cask ? "install --cask" : "install") \(item.name)",
                    forType: .string
                )
            }
        }
    }

    @ViewBuilder
    private var actionControl: some View {
        if item.isRemoteSuggestion {
            Text("GitHub")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let installed {
            if installed.updateAvailable {
                Button {
                    Task { await upgrade() }
                } label: {
                    workingLabel("Update")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .disabled(isWorking)
            } else if let appURL = AppLauncher.shared.appURL(for: item) {
                Button("Open") {
                    AppLauncher.shared.open(appURL)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            } else {
                Label("Installed", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                Task { await install() }
            } label: {
                workingLabel(item.type == .cask ? "Get" : "Install")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .disabled(isWorking)
        }
    }

    @ViewBuilder
    private func workingLabel(_ title: String) -> some View {
        if isWorking {
            ProgressView()
                .controlSize(.small)
        } else {
            Text(title)
        }
    }

    private func install() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await brewService.installFormula(item.id, type: item.type)
            AppLauncher.shared.rescan()
        } catch {
            brewService.report(error)
        }
    }

    private func upgrade() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await brewService.upgradeFormula(item.id, type: item.type)
            AppLauncher.shared.rescan()
        } catch {
            brewService.report(error)
        }
    }
}

/// Minimal wrapping layout for the suggested-search chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
