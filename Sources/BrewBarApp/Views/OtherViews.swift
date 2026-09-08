import SwiftUI
import BrewBarKit

public struct InstalledView: View {
    @StateObject private var viewModel = InstalledViewModel()

    public init() {}

    public var body: some View {
        VStack {
            HStack {
                TextField("Search installed packages...", text: $viewModel.filterState.searchQuery)
                    .textFieldStyle(.roundedBorder)

                Picker("Sort", selection: $viewModel.sortOrder) {
                    ForEach(SortOrderOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .frame(width: 180)
            }
            .padding()

            List(viewModel.filteredFormulas) { item in
                HStack {
                    Image(systemName: item.type == .cask ? "desktopcomputer" : "terminal")
                    VStack(alignment: .leading) {
                        Text(item.name).font(.headline)
                        Text(item.description).font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(item.currentVersion).font(.monospaced(.body)())
                }
            }
        }
        .navigationTitle("Installed")
        .task {
            await viewModel.refresh()
        }
    }
}

public struct UpdatesView: View {
    @StateObject private var viewModel = UpdatesViewModel()

    public init() {}

    public var body: some View {
        VStack {
            HStack {
                Text("\(viewModel.availableUpdates.count) Updates Available")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Update All") {
                    Task {
                        await viewModel.updateAll()
                    }
                }
                .buttonStyle(.glassProminent)
            }
            .padding()

            List(viewModel.availableUpdates) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name).font(.headline)
                        Text("\(item.currentVersion) ➜ \(item.latestVersion ?? "latest")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Update") {
                        Task {
                            await viewModel.updateItem(item)
                        }
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .navigationTitle("Updates")
        .task {
            await viewModel.checkForUpdates()
        }
    }
}

public struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @EnvironmentObject private var searchState: AppSearchState

    public init() {}

    public var body: some View {
        VStack {
            HStack {
                TextField("Search Homebrew formulas & casks...", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await viewModel.performSearch() }
                    }

                Button("Search") {
                    Task { await viewModel.performSearch() }
                }
                .buttonStyle(.glass)
            }
            .padding()

            if viewModel.isSearching {
                ProgressView()
                    .padding()
            }

            List(viewModel.results) { item in
                NavigationLink(destination: FormulaDetailView(formula: item)) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name).font(.headline)
                            Text(item.description).font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(item.type.displayName).font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Search")
        .onChange(of: searchState.pendingQuery) { _, newValue in
            guard !newValue.isEmpty else { return }
            viewModel.query = newValue
            searchState.pendingQuery = ""
            Task { await viewModel.performSearch() }
        }
        .task {
            guard !searchState.pendingQuery.isEmpty else { return }
            viewModel.query = searchState.pendingQuery
            searchState.pendingQuery = ""
            await viewModel.performSearch()
        }
    }
}

public struct FormulaDetailView: View {
    @StateObject private var viewModel: FormulaDetailViewModel

    public init(formula: FormulaItem) {
        _viewModel = StateObject(wrappedValue: FormulaDetailViewModel(formula: formula))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header: icon, title, developer/homepage, install button
                HStack(alignment: .top, spacing: 16) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: viewModel.formula.type == .cask ? "desktopcomputer" : "terminal")
                                .font(.system(size: 34))
                                .foregroundColor(.white)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 5, y: 3)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.formula.fullTitle ?? viewModel.formula.name)
                            .font(.largeTitle)
                            .bold()
                        if let homepage = viewModel.formula.homepage {
                            Text(homepage)
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                        }
                        Text(viewModel.formula.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(viewModel.formula.updateAvailable ? "Update" : "Install") {
                        Task { try? await viewModel.install() }
                    }
                    .buttonStyle(.glassProminent)
                }

                Divider()

                // Metadata row, mirroring an App Store product page's info strip
                HStack(spacing: 32) {
                    metadataColumn(label: "VERSION", value: viewModel.formula.currentVersion.isEmpty ? "—" : viewModel.formula.currentVersion)
                    metadataColumn(label: "TYPE", value: viewModel.formula.type.displayName)
                    metadataColumn(label: "LICENSE", value: viewModel.formula.license ?? "Unknown")
                    if let size = viewModel.formula.sizeInBytes {
                        metadataColumn(label: "SIZE", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                }

                Divider()

                Text("Description")
                    .font(.title2)
                    .bold()
                Text(viewModel.formula.description)
                    .font(.body)

                if !viewModel.formula.dependencies.isEmpty {
                    Divider()
                    Text("Dependencies")
                        .font(.title2)
                        .bold()
                    ForEach(viewModel.formula.dependencies) { dependency in
                        HStack {
                            Image(systemName: "shippingbox")
                                .foregroundColor(.secondary)
                            Text(dependency.name)
                            if dependency.isOptional {
                                Text("optional")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if let repository = viewModel.formula.repository {
                    Divider()
                    Text("Repository")
                        .font(.title2)
                        .bold()
                    Text(repository)
                        .font(.body)
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.formula.name)
    }

    @ViewBuilder
    private func metadataColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
    }
}

public struct PreferencesView: View {
    @StateObject private var viewModel = PreferencesViewModel()

    public init() {}

    public var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $viewModel.preferences.launchAtLogin)
                Toggle("Show menu bar icon", isOn: $viewModel.preferences.showMenuBarIcon)
                TextField("Homebrew Path", text: $viewModel.preferences.homebrewPrefix)
            }
        }
        .padding()
        .navigationTitle("Preferences")
        .onChange(of: viewModel.preferences) { _, _ in
            viewModel.save()
        }
    }
}
