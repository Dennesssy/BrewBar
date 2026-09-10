import SwiftUI
import BrewBarKit

/// Surfaces `brew services` — the background daemons (postgres, redis, nginx,
/// etc.) that Homebrew users otherwise manage entirely via Terminal. This is
/// the single most common terminal-workflow gap a menu-bar-style GUI app can
/// replace: toggling a dev service on/off.
public struct ServicesView: View {
    @StateObject private var manager = ServicesManager.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Services")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Refresh") {
                    Task { await manager.refresh() }
                }
                .buttonStyle(.glass)
                .disabled(manager.isLoading)
            }
            .padding()

            if let error = manager.lastError {
                Text(error.errorDescription ?? "Something went wrong.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            if manager.isLoading && manager.services.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.services.isEmpty {
                ContentUnavailableView(
                    "No Services",
                    systemImage: "gearshape.2",
                    description: Text("Formulas that register a background service (like postgresql or redis) will appear here once installed.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(manager.services) { service in
                    ServiceRowView(
                        service: service,
                        isBusy: manager.pendingActions.contains(service.name),
                        onStart: { Task { await manager.start(service.name) } },
                        onStop: { Task { await manager.stop(service.name) } },
                        onRestart: { Task { await manager.restart(service.name) } }
                    )
                }
            }
        }
        .navigationTitle("Services")
        .task {
            await manager.refresh()
        }
    }
}

private struct ServiceRowView: View {
    let service: BrewServiceStatus
    let isBusy: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.headline)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                controls
            }
        }
        .padding(.vertical, 4)
    }

    private var isRunning: Bool { service.status == "started" }

    private var statusLabel: String {
        switch service.status {
        case "started": return "Running"
        case "stopped", "none": return "Stopped"
        case "error": return "Error"
        default: return service.status.capitalized
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(isRunning ? Color.green : (service.status == "error" ? Color.red : Color.secondary))
            .frame(width: 8, height: 8)
    }

    @ViewBuilder
    private var controls: some View {
        if isRunning {
            Button("Restart", action: onRestart)
                .buttonStyle(.glass)
                .controlSize(.small)
            Button("Stop", action: onStop)
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        } else {
            Button("Start", action: onStart)
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        }
    }
}
