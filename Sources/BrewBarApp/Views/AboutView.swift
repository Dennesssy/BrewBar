// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI

public struct AboutView: View {
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                HStack(spacing: 16) {
                    Image(systemName: "mug.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.accentColor)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BrewBar")
                            .font(.system(size: 36, weight: .bold))
                        Text("Version 1.1.0")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("The native macOS GUI for Homebrew.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top)
                
                Divider()
                
                // Privacy and Compliance
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy & Compliance")
                        .font(.title2)
                        .bold()
                    Text("BrewBar is designed with privacy and security at its core:")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        PrivacyRow(icon: "lock.shield", title: "Local Execution", description: "All Homebrew commands are executed locally on your machine via standard macOS processes. We do not track what you install.")
                        PrivacyRow(icon: "key.fill", title: "Secure Keychain", description: "Your optional GitHub Personal Access Token is encrypted and stored exclusively in the macOS Keychain. It never leaves your device.")
                        PrivacyRow(icon: "eye.slash.fill", title: "Zero Analytics", description: "BrewBar contains zero tracking, telemetry, or analytics. Your usage data belongs to you.")
                    }
                    .padding(.top, 8)
                }
                
                Divider()
                
                // Version History
                VStack(alignment: .leading, spacing: 8) {
                    Text("Version History")
                        .font(.title2)
                        .bold()
                    
                    VersionRow(version: "1.1.0", date: "Sep 2026", notes: [
                        "Added live Apple-style download progress bars.",
                        "Integrated Secure Keychain for GitHub PAT.",
                        "Dynamic App Icons using GitHub avatars and Favicons.",
                        "Rich package details with live Stars and READMEs.",
                        "Brew Doctor diagnostic UI added.",
                        "Filtered out deprecated and disabled packages."
                    ])
                    
                    VersionRow(version: "1.0.0", date: "Aug 2026", notes: [
                        "Initial Release of BrewBar.",
                        "Native Swift 6 & SwiftUI architecture.",
                        "Semantic search and background package management."
                    ])
                }
                
                Divider()
                
                // Feedback
                VStack(alignment: .leading, spacing: 8) {
                    Text("Feedback & Support")
                        .font(.title2)
                        .bold()
                    Text("Have an issue, feature request, or just want to say hi? Reach out to us!")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        if let url = URL(string: "https://github.com/Dennesssy/BrewBar/issues") {
                            Link(destination: url) {
                                Label("Report an Issue", systemImage: "ladybug.fill")
                            }
                            .buttonStyle(.glass)
                        }
                        
                        if let url = URL(string: "mailto:support@brewbar.app") {
                            Link(destination: url) {
                                Label("Email Support", systemImage: "envelope.fill")
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(32)
        }
        .navigationTitle("About BrewBar")
    }
}

struct PrivacyRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct VersionRow: View {
    let version: String
    let date: String
    let notes: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(version)
                    .font(.headline)
                Spacer()
                Text(date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(notes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(note)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
    }
}
