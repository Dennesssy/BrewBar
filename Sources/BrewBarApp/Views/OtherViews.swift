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
                .buttonStyle(.borderedProminent)
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
                    .buttonStyle(.bordered)
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
    }
}

public struct FormulaDetailView: View {
    @StateObject private var viewModel: FormulaDetailViewModel

    public init(formula: FormulaItem) {
        _viewModel = StateObject(wrappedValue: FormulaDetailViewModel(formula: formula))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(viewModel.formula.name)
                            .font(.largeTitle)
                            .bold()
                        Text(viewModel.formula.description)
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Install") {
                        Task { try? await viewModel.install() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                Text("Reviews").font(.title2).bold()
                ForEach(viewModel.reviews) { review in
                    VStack(alignment: .leading) {
                        Text(review.authorUsername).font(.headline)
                        Text(review.comment).font(.body)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.formula.name)
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
