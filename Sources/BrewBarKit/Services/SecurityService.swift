// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation
import AppKit

@MainActor
public final class SecurityService: ObservableObject {
    public static let shared = SecurityService()

    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: BrewBarError?
    @Published public private(set) var lastScanResult: VulnsScanResult?

    private let processManager = ProcessManager()
    private let outputParser = OutputParser()
    private let errorHandler = ErrorHandler()

    public init() {}
    
    // CISA KEV JSON cache
    private var exploitedCache: Set<String>?
    private var exploitedCacheDate: Date?

    public func scanVulnerabilities() async {
        isLoading = true
        defer { isLoading = false }

        let prefs = await LocalStorageManager.shared.loadPreferences()
        guard prefs.allowVulnerabilityLookups else { return }
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).vulns(json: true)

        do {
            let output = try await processManager.execute(
                executablePath: builder.executablePath,
                arguments: builder.buildArguments(),
                timeout: 120,
                allowNonZeroExit: true,
                extraEnvironment: ["HOMEBREW_NO_AUTO_UPDATE": "1"]
            )
            
            // Check for "Unknown command" which happens on old brew versions
            if output.contains("Unknown command") || output.contains("brew help") || output.contains("unknown command") {
                self.lastScanResult = VulnsScanResult(vulnerablePackages: [], skippedPackages: [], isOlderHomebrew: true)
                self.lastError = nil
                return
            }

            var (vulnerable, skipped) = outputParser.parseVulnsJSON(output)
            
            if skipped.isEmpty {
                 let skippedBuilder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).vulnsListSkipped()
                 if let skippedOutput = try? await processManager.execute(
                    executablePath: skippedBuilder.executablePath,
                    arguments: skippedBuilder.buildArguments(),
                    timeout: 60,
                    allowNonZeroExit: true,
                    extraEnvironment: ["HOMEBREW_NO_AUTO_UPDATE": "1"]
                 ) {
                     for line in skippedOutput.components(separatedBy: .newlines) {
                         let trimmed = line.trimmingCharacters(in: .whitespaces)
                         if !trimmed.isEmpty && !trimmed.contains("Warning") && !trimmed.contains("Error") {
                             skipped.append(SkippedPackage(package: trimmed, reason: "Skipped (no additional reason provided by --list-skipped)"))
                         }
                     }
                 }
            }
            
            // Enrich with CISA Known Exploited Vulnerabilities if we have vulnerabilities
            if !vulnerable.isEmpty {
                if let knownExploited = try? await getKnownExploitedCVEs() {
                    vulnerable = vulnerable.map { pkg in
                        let isExploited = pkg.vulnerabilities.contains { knownExploited.contains($0.cve.uppercased()) }
                        return VulnerablePackage(package: pkg.package, version: pkg.version, vulnerabilities: pkg.vulnerabilities, isExploited: isExploited)
                    }
                }
            }
            
            vulnerable.sort { p1, p2 in
                let maxSev1 = p1.vulnerabilities.map { $0.severityScore }.max() ?? 0
                let maxSev2 = p2.vulnerabilities.map { $0.severityScore }.max() ?? 0
                return maxSev1 > maxSev2
            }

            self.lastScanResult = VulnsScanResult(vulnerablePackages: vulnerable, skippedPackages: skipped, isOlderHomebrew: false)
            self.lastError = nil
        } catch {
            self.lastError = errorHandler.handle(error)
        }
    }
    
    private func getKnownExploitedCVEs() async throws -> Set<String> {
        if let cache = exploitedCache, let date = exploitedCacheDate, date.timeIntervalSinceNow > -86400 {
            return cache
        }
        
        let urlString = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
        guard let url = URL(string: urlString) else { return [] }
        
        struct CISAFeed: Codable {
            struct Vulnerability: Codable {
                let cveID: String
            }
            let vulnerabilities: [Vulnerability]
        }
        
        let data = try await HTTPClient.shared.fetchRawData(url)
        let feed = try JSONDecoder().decode(CISAFeed.self, from: data)
        let cves = Set(feed.vulnerabilities.map { $0.cveID.uppercased() })
        
        self.exploitedCache = cves
        self.exploitedCacheDate = Date()
        
        return cves
    }

    public func upgradePackage(_ name: String) async throws {
        let item = FormulaItem(id: name, name: name, description: "", currentVersion: "", type: .formula)
        try await PackageService.shared.upgradePackage(item)
    }

    // Host checks (read-only, argv-only commands)
    public func getHostChecks() async -> (casks: [String], taps: [String], ports: [String]) {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        
        // Casks
        var casksReport: [String] = []
        if let caskOut = try? await processManager.execute(executablePath: prefs.homebrewPrefix + "/bin/brew", arguments: ["list", "--cask"]) {
            let casks = caskOut.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for cask in casks.prefix(10) { // Limit to 10 for speed
                if let infoOut = try? await processManager.execute(executablePath: prefs.homebrewPrefix + "/bin/brew", arguments: ["info", "--cask", cask]) {
                    let lines = infoOut.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains(".app") && line.contains("App") {
                            let pathParts = line.components(separatedBy: " (App)")
                            if let appPath = pathParts.first?.trimmingCharacters(in: .whitespaces) {
                                let verifyOut = (try? await processManager.execute(executablePath: "/usr/bin/codesign", arguments: ["--verify", "--verbose", appPath], allowNonZeroExit: true)) ?? "could not check"
                                casksReport.append("\(cask): \(verifyOut.contains("valid on disk") ? "valid" : "could not check")")
                                break
                            }
                        }
                    }
                }
            }
        }
        
        // Taps (non-official)
        var tapsReport: [String] = []
        if let tapOut = try? await processManager.execute(executablePath: prefs.homebrewPrefix + "/bin/brew", arguments: ["tap"], extraEnvironment: ["HOMEBREW_NO_AUTO_UPDATE": "1"]) {
            let taps = tapOut.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for tap in taps {
                if !tap.hasPrefix("homebrew/") {
                    tapsReport.append(tap)
                }
            }
        }
        
        // Ports
        var portsReport: [String] = []
        if let lsofOut = try? await processManager.execute(executablePath: "/usr/sbin/lsof", arguments: ["-PiTCP", "-sTCP:LISTEN"], allowNonZeroExit: true) {
            let lines = lsofOut.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("homebrew") { // crude filter
                    let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count > 8 {
                        portsReport.append("\(parts[0]) on \(parts[8])")
                    }
                }
            }
        }
        
        return (casksReport, tapsReport, portsReport)
    }
}
