import SwiftUI
import BrewBarKit

public struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Updates Banner
                UpdatesBannerView()

                // Featured Section
                Text("Featured Packages")
                    .font(.title2)
                    .bold()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.featured) { item in
                            PackageCardView(item: item)
                        }
                    }
                }

                // Recommended Section
                Text("Recommended for You")
                    .font(.title2)
                    .bold()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                    ForEach(viewModel.recommended) { item in
                        PackageCardView(item: item)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Home")
        .task {
            try? await BrewService.shared.checkForUpdates()
        }
    }
}

public struct UpdatesBannerView: View {
    @ObservedObject private var brewService = BrewService.shared

    public init() {}

    public var body: some View {
        if !brewService.availableUpdates.isEmpty {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(brewService.availableUpdates.count) Updates Available")
                        .font(.headline)
                    Text("Formulas and casks are ready to upgrade.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Update All") {
                    Task {
                        try? await brewService.upgradeAll()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

public struct PackageCardView: View {
    let item: FormulaItem

    public init(item: FormulaItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.type == .cask ? "desktopcomputer" : "terminal")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Spacer()
                Text(item.type.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }

            Text(item.name)
                .font(.headline)
                .lineLimit(1)

            Text(item.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Spacer()

            Button("Install") {
                Task {
                    try? await BrewService.shared.installFormula(item.name)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 220, height: 160)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(radius: 2)
    }
}
