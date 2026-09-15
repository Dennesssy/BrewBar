// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import SwiftData
import BrewBarKit

public struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HistoryRecord.timestamp, order: .reverse) private var records: [HistoryRecord]
    
    public init() {}
    
    public var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock", description: Text("Packages you install, upgrade, or uninstall will appear here."))
            } else {
                List {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(record.packageName)
                                    .font(.headline)
                                Spacer()
                                Text(record.timestamp, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(record.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Label(record.action.capitalized, systemImage: iconForAction(record.action))
                                    .font(.subheadline)
                                    .foregroundColor(colorForAction(record.action))
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(record.packageType.capitalized)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let details = record.details, !details.isEmpty {
                                DisclosureGroup("Terminal Output") {
                                    Text(details)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(Color(NSColor.windowBackgroundColor))
                                        .cornerRadius(4)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    HistoryStore.shared.clearAll()
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
            }
        }

    }
    
    private func iconForAction(_ action: String) -> String {
        switch action.lowercased() {
        case "install": return "square.and.arrow.down"
        case "uninstall": return "trash"
        case "upgrade", "upgradeall": return "arrow.triangle.2.circlepath"
        default: return "circle"
        }
    }
    
    private func colorForAction(_ action: String) -> Color {
        switch action.lowercased() {
        case "install": return .green
        case "uninstall": return .red
        case "upgrade", "upgradeall": return .orange
        default: return .primary
        }
    }
}
