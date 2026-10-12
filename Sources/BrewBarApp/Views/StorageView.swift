// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

/// An `ncdu`-style disk-usage browser over Homebrew's real directories
/// (Cellar, Caskroom, download cache, logs) — biggest items first, with a
/// proportional bar per row and breadcrumb drill-down, matching the classic
/// terminal tool's mental model for users who already reach for it.
public struct StorageView: View {
    @StateObject private var viewModel = StorageViewModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            breadcrumbBar
            Divider()
            content
        }
        .navigationTitle("Storage")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            if viewModel.rows.isEmpty {
                await viewModel.loadRoot()
            }
        }
        .alert("Uninstall \"\(viewModel.pendingUninstall?.name ?? "")\"?", isPresented: Binding(
            get: { viewModel.pendingUninstall != nil },
            set: { if !$0 { viewModel.pendingUninstall = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                Task { await viewModel.performPendingUninstall() }
            }
        } message: {
            Text("This runs `brew uninstall` — the only safe way to remove a Homebrew package's files without corrupting Homebrew's own records.")
        }
        .alert("Move \"\(viewModel.pendingTrash?.name ?? "")\" to the Trash?", isPresented: Binding(
            get: { viewModel.pendingTrash != nil },
            set: { if !$0 { viewModel.pendingTrash = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task { await viewModel.performPendingTrash() }
            }
        } message: {
            Text("It can be restored from the Trash afterward.")
        }
        .alert("Couldn't Complete Action", isPresented: Binding(
            get: { viewModel.actionError != nil },
            set: { if !$0 { viewModel.actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                Button(crumb.title) {
                    Task { await viewModel.jump(to: index) }
                }
                .buttonStyle(.plain)
                .font(index == viewModel.breadcrumbs.count - 1 ? .headline : .subheadline)
                .foregroundColor(index == viewModel.breadcrumbs.count - 1 ? .primary : .accentColor)
                .disabled(index == viewModel.breadcrumbs.count - 1)

                if index < viewModel.breadcrumbs.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !viewModel.rows.isEmpty {
                Text(ByteCountFormatter.string(fromByteCount: Int64(viewModel.totalBytes), countStyle: .file))
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.rows.isEmpty {
            ProgressView("Scanning \(viewModel.breadcrumbs.last?.title ?? "Homebrew")…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.rows.isEmpty {
            ContentUnavailableView(
                viewModel.isAtRoot ? "No Homebrew Directories Found" : "Empty",
                systemImage: "externaldrive",
                description: Text(viewModel.isAtRoot
                    ? "BrewBar couldn't resolve Cellar, Caskroom, or cache paths for this Homebrew installation."
                    : "This location has nothing in it.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(viewModel.rows) { row in
                    StorageRowView(row: row, maxBytes: viewModel.maxRowBytes)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard row.isNavigable else { return }
                            Task { await viewModel.drillIn(row) }
                        }
                        .contextMenu {
                            Button("Reveal in Finder") {
                                viewModel.revealInFinder(row)
                            }
                            if row.uninstallTarget != nil {
                                Button("Uninstall…", role: .destructive) {
                                    viewModel.confirmUninstall(row)
                                }
                            } else if row.isDirectlyTrashable {
                                Button("Move to Trash…", role: .destructive) {
                                    viewModel.confirmTrash(row)
                                }
                            }
                        }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct StorageRowView: View {
    let row: StorageRow
    let maxBytes: UInt64

    private var fraction: Double {
        guard maxBytes > 0 else { return 0 }
        return Double(row.sizeInBytes) / Double(maxBytes)
    }

    private var systemImage: String {
        switch row.kind {
        case .category(let category): return category.systemImage
        case .cellarFormula: return "terminal.fill"
        case .caskApp: return "app.fill"
        case .nested: return row.isDirectory ? "folder" : "doc"
        }
    }

    private var subtitle: String? {
        switch row.kind {
        case .category(let category): return category.subtitle
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                        Capsule()
                            .fill(Color.accentColor.opacity(0.6))
                            .frame(width: max(0, geo.size.width * fraction))
                    }
                }
                .frame(height: 5)
                .padding(.top, 2)
            }

            Spacer(minLength: 12)

            Text(ByteCountFormatter.string(fromByteCount: Int64(row.sizeInBytes), countStyle: .file))
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)

            if row.isNavigable {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
    }
}
