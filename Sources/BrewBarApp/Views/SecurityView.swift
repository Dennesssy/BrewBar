// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

public struct SecurityView: View {
    @StateObject private var securityService = SecurityService.shared
    @StateObject private var prefs = PreferencesViewModel()
    @State private var hostCasks: [String] = []
    @State private var hostTaps: [String] = []
    @State private var hostPorts: [String] = []
    @State private var didLoadHostChecks = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !prefs.preferences.allowVulnerabilityLookups {
                    privacyNotice
                } else {
                    scanSection
                }
                
                hostChecksSection
            }
            .padding()
        }
        .navigationTitle("Security")
        .task {
            if prefs.preferences.allowVulnerabilityLookups && securityService.lastScanResult == nil {
                await securityService.scanVulnerabilities()
            }
            if !didLoadHostChecks {
                let checks = await securityService.getHostChecks()
                hostCasks = checks.casks
                hostTaps = checks.taps
                hostPorts = checks.ports
                didLoadHostChecks = true
            }
        }
    }

    private var privacyNotice: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("Vulnerability Scanning")
                .font(.title2).bold()
            Text("BrewBar can run `brew vulns` to check your installed packages against known vulnerabilities from OSV.dev. This sends your package names and versions to OSV.dev.")
            
            Toggle("Allow vulnerability lookups", isOn: $prefs.preferences.allowVulnerabilityLookups)
                .onChange(of: prefs.preferences.allowVulnerabilityLookups) { _, newValue in
                    prefs.save()
                    if newValue {
                        Task { await securityService.scanVulnerabilities() }
                    }
                }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var scanSection: some View {
        HStack {
            Text("Vulnerabilities")
                .font(.title2).bold()
            Spacer()
            Button("Rescan") {
                Task { await securityService.scanVulnerabilities() }
            }
            .disabled(securityService.isLoading)
        }
        
        if securityService.isLoading {
            ProgressView("Scanning packages...")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        } else if let err = securityService.lastError {
            Text("Scan failed: \(err.localizedDescription)")
                .foregroundColor(.red)
        } else if let result = securityService.lastScanResult {
            if result.isOlderHomebrew {
                Text("Your Homebrew version does not support `brew vulns`. Please update Homebrew to use this feature.")
                    .foregroundColor(.secondary)
            } else {
                if result.vulnerablePackages.isEmpty && result.skippedPackages.isEmpty {
                    Text("No vulnerabilities found.")
                        .foregroundColor(.green)
                } else {
                    ForEach(result.vulnerablePackages) { pkg in
                        vulnerablePackageView(pkg)
                    }
                    if !result.skippedPackages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Not checked")
                                .font(.headline)
                            ForEach(result.skippedPackages) { skipped in
                                HStack {
                                    Text(skipped.package).bold()
                                    Text(skipped.reason).foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 8))
                    }
                }
            }
        }
    }
    
    private func vulnerablePackageView(_ pkg: VulnerablePackage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pkg.package).font(.headline)
                Text(pkg.version).foregroundColor(.secondary)
                Spacer()
                if pkg.isExploited {
                    Text("Known Exploited")
                        .font(.caption).bold()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                if pkg.vulnerabilities.contains(where: { $0.fixedIn != nil }) {
                    Button("Upgrade") {
                        Task {
                            try? await securityService.upgradePackage(pkg.package)
                            await securityService.scanVulnerabilities()
                        }
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            
            ForEach(pkg.vulnerabilities) { vuln in
                HStack(alignment: .top) {
                    Circle()
                        .fill(severityColor(vuln.severity))
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                    VStack(alignment: .leading) {
                        Text(vuln.cve).bold()
                        Text(vuln.summary).font(.subheadline)
                        if let fixedIn = vuln.fixedIn {
                            Text("Fixed in: \(fixedIn)").font(.caption).foregroundColor(.green)
                        }
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
    }
    
    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "critical": return .red
        case "high": return .orange
        case "medium": return .yellow
        case "low": return .blue
        default: return .gray
        }
    }
    
    @ViewBuilder
    private var hostChecksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This Mac")
                .font(.title2).bold()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Casks (Codesign & Quarantine)")
                    .font(.headline)
                if hostCasks.isEmpty {
                    Text("None checked or no casks found.").foregroundColor(.secondary)
                } else {
                    ForEach(hostCasks, id: \.self) { c in
                        Text(c)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Non-official Taps")
                    .font(.headline)
                if hostTaps.isEmpty {
                    Text("None").foregroundColor(.secondary)
                } else {
                    ForEach(hostTaps, id: \.self) { t in
                        Text(t)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Listening Homebrew Services")
                    .font(.headline)
                if hostPorts.isEmpty {
                    Text("None found.").foregroundColor(.secondary)
                } else {
                    ForEach(hostPorts, id: \.self) { p in
                        Text(p)
                    }
                }
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
