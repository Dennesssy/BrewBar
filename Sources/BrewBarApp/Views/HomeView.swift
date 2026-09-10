import SwiftUI
import BrewBarKit

public struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                UpdatesBannerView()

                ServicesStatusStripView()

                if !viewModel.recentlyUpdated.isEmpty {
                    PackageCarouselSection(title: "Recently Installed", items: viewModel.recentlyUpdated)
                }

                PackageCarouselSection(title: "Featured Packages", items: viewModel.featured)

                PackageCarouselSection(title: "Recommended for You", items: viewModel.recommended)
            }
            .padding()
        }
        .navigationTitle("Home")
        .task {
            try? await BrewService.shared.checkForUpdates()
            try? await BrewService.shared.refreshInstalledPackages()
            viewModel.loadData()
            await ServicesManager.shared.refresh()
        }
    }
}

/// Compact at-a-glance summary of running/stopped brew services, so the
/// Home page surfaces real machine state instead of only editorial content.
/// Tapping a chip jumps to the full Services tab.
public struct ServicesStatusStripView: View {
    @ObservedObject private var manager = ServicesManager.shared

    public init() {}

    private var registeredServices: [BrewServiceStatus] {
        manager.services.filter { $0.status != "none" }
    }

    public var body: some View {
        if !registeredServices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Services")
                    .font(.title2)
                    .bold()

                ScrollView(.horizontal, showsIndicators: false) {
                    // Multiple .glassEffect() views updating in the same frame
                    // without a shared GlassEffectContainer trips a fatal
                    // "tried to update multiple times per frame" error —
                    // matches the pattern PackageCarouselSection already uses.
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(registeredServices, id: \.id) { service in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(service.status == "started" ? Color.green : (service.status == "error" ? Color.red : Color.secondary))
                                        .frame(width: 7, height: 7)
                                    Text(service.name)
                                        .font(.caption)
                                        .bold()
                                    Text(service.status == "started" ? "Running" : (service.status == "error" ? "Error" : "Stopped"))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .glassEffect(.regular, in: .rect(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
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
                .buttonStyle(.glassProminent)
            }
            .padding()
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.3)), in: .rect(cornerRadius: 12))
        }
    }
}
