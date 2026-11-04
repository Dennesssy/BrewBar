// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation
import AppKit
import Darwin

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
                         // Formula names have no spaces, unlike the status lines around them.
                         if !trimmed.isEmpty && !trimmed.contains(" ") {
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
        let brew = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).executablePath
        
        // Casks
        var casksReport: [String] = []
        if let caskOut = try? await processManager.execute(executablePath: brew, arguments: ["list", "--cask"]) {
            let casks = caskOut.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for cask in casks.prefix(10) { // Limit to 10 for speed
                if let infoOut = try? await processManager.execute(executablePath: brew, arguments: ["info", "--cask", cask]) {
                    let lines = infoOut.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains(".app") && line.contains("App") {
                            let pathParts = line.components(separatedBy: " (App)")
                            if let appName = pathParts.first?.trimmingCharacters(in: .whitespaces) {
                                // `brew info --cask` prints the bundle name ("Foo.app (App)"), not its path.
                                let appPath = appName.hasPrefix("/") ? appName : "/Applications/\(appName)"
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
        if let tapOut = try? await processManager.execute(executablePath: brew, arguments: ["tap"], extraEnvironment: ["HOMEBREW_NO_AUTO_UPDATE": "1"]) {
            let taps = tapOut.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for tap in taps {
                if !tap.hasPrefix("homebrew/") {
                    tapsReport.append(tap)
                }
            }
        }
        
        // Ports: TCP listeners whose executable lives under the Homebrew prefix.
        // lsof's COMMAND column is truncated, so match on the resolved executable path instead.
        var portsReport: [String] = []
        let homebrewPrefix = URL(fileURLWithPath: brew).deletingLastPathComponent().deletingLastPathComponent().path
        if let lsofOut = try? await processManager.execute(executablePath: "/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"], allowNonZeroExit: true) {
            var pathByPid: [Int32: String] = [:]
            var reported = Set<String>()
            for listener in Self.parseListeners(lsofOut) {
                if pathByPid[listener.pid] == nil {
                    pathByPid[listener.pid] = Self.executablePath(forPid: listener.pid) ?? ""
                }
                guard let path = pathByPid[listener.pid], !path.isEmpty,
                      Self.isHomebrewExecutable(path, prefix: homebrewPrefix) else { continue }
                let entry = "\(listener.command) (pid \(listener.pid)) on \(listener.address)"
                if reported.insert(entry).inserted {
                    portsReport.append(entry)
                }
            }
        }

        return (casksReport, tapsReport, portsReport)
    }

    /// One TCP listening socket parsed from `lsof -Fpcn` output.
    struct ListeningSocket: Equatable, Sendable {
        let pid: Int32
        let command: String
        let address: String
    }

    /// Parses `lsof -nP -iTCP -sTCP:LISTEN -Fpcn` field output. Each `p` line starts a
    /// process record, `c` names it, and every `n` line is one listening address.
    /// Lines with unknown tags, bad pids, or addresses before any valid `p` are skipped.
    nonisolated static func parseListeners(_ lsofFieldOutput: String) -> [ListeningSocket] {
        var listeners: [ListeningSocket] = []
        var pid: Int32?
        var command = ""
        for line in lsofFieldOutput.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value).flatMap { $0 > 0 ? $0 : nil }
                command = ""
            case "c":
                command = value
            case "n":
                guard let pid, !value.isEmpty else { continue }
                listeners.append(ListeningSocket(pid: pid, command: command, address: value))
            default:
                continue
            }
        }
        return listeners
    }

    /// Resolves the on-disk executable of a process via `proc_pidpath`, or nil if the kernel won't say.
    nonisolated static func executablePath(forPid pid: Int32) -> String? {
        let maxPathInfoSize = 4096 // PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN)
        var buffer = [CChar](repeating: 0, count: maxPathInfoSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// True when `path` is inside the Homebrew prefix. A path boundary is required, so
    /// `/opt/homebrewevil/...` does not match `/opt/homebrew`.
    nonisolated static func isHomebrewExecutable(_ path: String, prefix: String) -> Bool {
        let root = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        return !root.isEmpty && path.hasPrefix(root + "/")
    }
}
