// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

public struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var catalog = HomebrewCatalogService.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                UpdatesBannerView()

                ServicesStatusStripView()

                if viewModel.isLoading && viewModel.featured.isEmpty {
                    ProgressView("Loading the Homebrew catalog…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else if viewModel.featured.isEmpty {
                    catalogUnavailableState
                } else {
                    if !viewModel.recentlyUpdated.isEmpty {
                        PackageCarouselSection(title: "Recently Installed", items: viewModel.recentlyUpdated)
                    }

                    PackageCarouselSection(title: "Featured Packages", items: viewModel.featured)

                    if !viewModel.recommended.isEmpty {
                        PackageCarouselSection(title: "Recommended for You", items: viewModel.recommended)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Home")
        .task {
            Task { try? await BrewService.shared.checkForUpdates() }
            Task { try? await BrewService.shared.refreshInstalledPackages() }
            Task { await viewModel.loadData() }
            Task { await ServicesManager.shared.refresh() }
        }

    }

    private var catalogUnavailableState: some View {
        ContentUnavailableView {
            Label("Couldn’t Load the Homebrew Catalog", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Recommendations need a network connection the first time they load.")
        } actions: {
            Button("Try Again") {
                Task {
                    await catalog.refresh()
                    await viewModel.loadData()
                }
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
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
    @State private var showConfirmation = false
    @State private var isUpdating = false

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
                Button(isUpdating ? "Updating…" : "Update All") {
                    showConfirmation = true
                }
                .buttonStyle(.glassProminent)
                .disabled(isUpdating)
            }
            .padding()
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.3)), in: .rect(cornerRadius: 12))
            .alert("Update All Packages?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Update") {
                    Task { await updateAll() }
                }
            } message: {
                Text("BrewBar will upgrade all \(brewService.availableUpdates.count) packages with Homebrew.")
            }
        }
    }

    private func updateAll() async {
        isUpdating = true
        defer { isUpdating = false }
        do {
            try await brewService.upgradeAll()
        } catch {
            brewService.report(error)
        }
    }
}
