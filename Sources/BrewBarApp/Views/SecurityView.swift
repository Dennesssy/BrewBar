// Copyright © 2026 Dennis Stewart. All rights reserved.

import SwiftUI
import BrewBarKit

public struct SecurityView: View {
    @StateObject private var securityService = SecurityService.shared
    @StateObject private var nodeService = NodeVulnerabilityService.shared
    @StateObject private var prefs = PreferencesViewModel.shared
    @State private var hostCasks: [String] = []
    @State private var hostTaps: [String] = []
    @State private var hostPorts: [String] = []
    @State private var didLoadHostChecks = false
    @State private var contentWidth: CGFloat = 0

    /// Below this width the two scan columns stack.
    private let sideBySideWidth: CGFloat = 760

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !prefs.preferences.allowVulnerabilityLookups {
                    privacyNotice
                } else {
                    scanHeader
                    if contentWidth >= sideBySideWidth {
                        HStack(alignment: .top, spacing: 24) {
                            brewColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                            nodeColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            brewColumn
                            nodeColumn
                        }
                    }
                }
                
                hostChecksSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        }
        .navigationTitle("Security")
        .task {
            // Ask storage directly: the view model may still be loading when this runs.
            async let scans: Void = scanIfNeeded()
            if !didLoadHostChecks {
                let checks = await securityService.getHostChecks()
                hostCasks = checks.casks
                hostTaps = checks.taps
                hostPorts = checks.ports
                didLoadHostChecks = true
            }
            _ = await scans
        }
    }

    private var privacyNotice: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("Vulnerability Scanning")
                .font(.title2).bold()
            Text("BrewBar can run `brew vulns` and check your global npm packages against known vulnerabilities from OSV.dev. This sends your package names and versions to OSV.dev.")
            
            Toggle("Allow vulnerability lookups", isOn: $prefs.preferences.allowVulnerabilityLookups)
                .onChange(of: prefs.preferences.allowVulnerabilityLookups) { _, newValue in
                    prefs.save()
                    if newValue {
                        Task { await scanAll() }
                    }
                }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var scanHeader: some View {
        HStack {
            Text("Vulnerabilities")
                .font(.largeTitle).bold()
            Spacer()
            Button("Scan All") {
                Task { await scanAll() }
            }
            .buttonStyle(.glassProminent)
            .disabled(securityService.isLoading || nodeService.isLoading)
        }
    }

    private var nodeColumn: some View {
        NodeVulnerabilitySection(service: nodeService)
    }

    private func scanIfNeeded() async {
        let saved = await LocalStorageManager.shared.loadPreferences()
        guard saved.allowVulnerabilityLookups,
              securityService.lastScanResult == nil, nodeService.lastResult == nil else { return }
        await scanAll()
    }

    /// Runs `brew vulns` and the global npm scan at the same time.
    private func scanAll() async {
        async let brew: Void = securityService.scanVulnerabilities()
        async let node: Void = nodeService.scan()
        _ = await (brew, node)
    }

    private var brewColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            scanSection
        }
    }

    @ViewBuilder
    private var scanSection: some View {
        HStack {
            Text("Homebrew Formulae")
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
                        DisclosureGroup("Not checked (\(result.skippedPackages.count))") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(result.skippedPackages) { skipped in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(skipped.package).bold()
                                        Text(skipped.reason)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                        .font(.headline)
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 8))
                    }
                }
            }
        } else {
            Text("Not scanned yet.")
                .foregroundColor(.secondary)
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
                        .fill(vulnerabilitySeverityColor(vuln.severity))
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
