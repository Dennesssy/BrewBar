// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

public struct ConfigView: View {
    @State private var sections: [BrewConfigSection] = []
    @State private var isLoading = false
    @State private var error: String?
    @ObservedObject private var brewService = BrewService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Configuration")
                    .font(.title2)
                    .bold()
                Spacer()
                Button(action: copyToClipboard) {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)
                .disabled(sections.isEmpty)
                
                Button("Refresh") {
                    Task { await loadConfig() }
                }
                .buttonStyle(.glass)
                .disabled(isLoading)
            }
            .padding()
            
            if let err = error {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            if isLoading && sections.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(section.content)
                            .font(.system(.body, design: .monospaced))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Configuration")
        .task {
            if sections.isEmpty {
                await loadConfig()
            }
        }
    }
    
    private func loadConfig() async {
        isLoading = true
        error = nil
        do {
            sections = try await brewService.config()
        } catch {
            self.error = "Failed to load config: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    private func copyToClipboard() {
        let text = sections.map { "\($0.title): \($0.content)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
