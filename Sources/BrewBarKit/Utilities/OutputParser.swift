// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

public struct BrewListOutput: Codable, Sendable {
    public let formulae: [BrewFormula]
    public let casks: [BrewCask]
}

public struct BrewOutdatedOutput: Codable, Sendable {
    public let formulae: [BrewFormula]
    public let casks: [BrewOutdatedCask]
}

/// `brew outdated --json=v2` casks use a different shape than `brew info`'s:
/// `name` is the bare token string (not `[String]`) and there is no `token`
/// key at all (verified against live `brew outdated --json=v2` output).
/// Reusing `BrewCask` here throws on any response containing a cask, since
/// `token` is required and `name` is typed as `[String]?`.
public struct BrewOutdatedCask: Codable, Sendable {
    public let name: String
    public let installed_versions: [String]?
    public let current_version: String?
}

/// One installed keg entry from `brew info --json=v2 --installed`.
/// `time` is epoch seconds; a formula can have several kegs installed.
public struct BrewInstalledKeg: Codable, Sendable {
    public let version: String?
    public let time: Double?
}

public struct BrewFormula: Codable, Sendable {
    public let name: String
    public let full_name: String?
    public let desc: String?
    public let installed_versions: [String]?
    public let current_version: String?
    public let outdated: Bool?
    public let homepage: String?
    public let license: String?
    public let pinned: Bool?
    public let linked_keg: String?
    public let installed: [BrewInstalledKeg]?
    /// Runtime dependency names as plain strings (e.g. "fmt", "simdutf").
    public let dependencies: [String]?
    /// Deps satisfied by macOS itself — still real dependencies for tree views.
    public let uses_from_macos: [String]?
}

public struct BrewCask: Codable, Sendable {
    public let token: String
    public let name: [String]?
    public let desc: String?
    public let installed_versions: [String]?
    public let current_version: String?
    public let outdated: Bool?
    public let homepage: String?
    public let pinned: Bool?
    /// Latest version known to the tap (may carry a ",build" suffix).
    public let version: String?
    /// Installed version spec, e.g. "1.13.0" or "1.1.19,4894004681244672".
    /// `brew info --json=v2 --installed` emits this as a string, not an array.
    public let installed: String?
    /// Epoch seconds when the cask was installed.
    public let installed_time: Double?
}

/// Matches the real `brew services list --json` schema: an array of objects
/// with name/status/user/file/exit_code (verified against live output).
public struct BrewServiceEntry: Codable, Sendable {
    public let name: String
    public let status: String
    public let user: String?
    public let file: String?
}

public struct OutputParser: Sendable {
    public init() {}


    private struct VulnsJSONVulnerability: Codable {
        let id: String? // CVE or GHSA
        let cve: String?
        let summary: String?
        let severity: String?
        let fixed_in: String?
    }
    
    private struct VulnsJSONPackage: Codable {
        let name: String
        let version: String?
        let vulnerabilities: [VulnsJSONVulnerability]?
    }
    
    private struct VulnsJSONSkipped: Codable {
        let name: String
        let reason: String?
    }
    
    private struct VulnsJSONRoot: Codable {
        let vulnerabilities: [VulnsJSONPackage]?
        let skipped: [VulnsJSONSkipped]?
    }

    /// `brew doctor --json` → `{"tier": 1, "findings": [{text, remediation}]}`.
    private struct DoctorJSONRoot: Codable {
        let findings: [DoctorJSONFinding]
    }

    private struct DoctorJSONFinding: Codable {
        let text: String
        let remediation: Remediation?

        struct Remediation: Codable {
            let commands: [String]?
            let text: String?
        }
    }


    public func parseVulnsJSON(_ output: String) -> (vulnerablePackages: [VulnerablePackage], skippedPackages: [SkippedPackage]) {
        guard let data = output.data(using: .utf8) else { return ([], []) }
        
        do {
            let root = try JSONDecoder().decode(VulnsJSONRoot.self, from: data)
            
            var vulnerablePackages: [VulnerablePackage] = []
            if let packages = root.vulnerabilities {
                for pkg in packages {
                    var vulns: [Vulnerability] = []
                    if let rawVulns = pkg.vulnerabilities {
                        for v in rawVulns {
                            vulns.append(Vulnerability(
                                cve: v.cve ?? v.id ?? "Unknown",
                                summary: v.summary ?? "No summary provided",
                                severity: v.severity ?? "Unknown",
                                fixedIn: v.fixed_in
                            ))
                        }
                    }
                    
                    if !vulns.isEmpty {
                        vulnerablePackages.append(VulnerablePackage(
                            package: pkg.name,
                            version: pkg.version ?? "Unknown",
                            vulnerabilities: vulns.sorted(by: { $0.severityScore > $1.severityScore })
                        ))
                    }
                }
            }
            
            var skippedPackages: [SkippedPackage] = []
            if let skipped = root.skipped {
                for s in skipped {
                    skippedPackages.append(SkippedPackage(
                        package: s.name,
                        reason: s.reason ?? "Unknown reason"
                    ))
                }
            }
            
            return (vulnerablePackages, skippedPackages)
        } catch {
            return ([], [])
        }
    }

    public func parseDoctor(_ output: String) -> [DoctorIssue] {
        // Try parsing as JSON first
        if let data = output.data(using: .utf8),
           let root = try? JSONDecoder().decode(DoctorJSONRoot.self, from: data) {
            // Every doctor finding is printed as "Warning:" in text mode;
            // the JSON form carries no separate error/warning distinction.
            return root.findings.map { finding in
                let lines = finding.text.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                let remediation = finding.remediation?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let details = (Array(lines.dropFirst()) + (remediation.isEmpty ? [] : [remediation]))
                    .joined(separator: "\n")
                let fixCommand = finding.remediation?.commands?.first
                    .map { $0.components(separatedBy: " ").filter { !$0.isEmpty } }
                    .map { $0.first == "brew" ? Array($0.dropFirst()) : $0 }
                return DoctorIssue(severity: .warning, summary: lines.first ?? "Unknown issue", details: details, fixCommand: fixCommand)
            }
        }
        
        // Fallback to plain text parsing
        // Brew doctor output format:
        // Warning: Some warning summary here
        //   Details line 1
        //   Details line 2
        var issues: [DoctorIssue] = []
        let blocks = output.components(separatedBy: "\nWarning: ")
        
        for (index, block) in blocks.enumerated() {
            let isFirst = index == 0
            let text = isFirst ? block : "Warning: " + block
            
            if text.starts(with: "Warning: ") || text.starts(with: "Error: ") {
                let isError = text.starts(with: "Error: ")
                let severity: DoctorIssue.Severity = isError ? .error : .warning
                
                let issueText = text.replacingOccurrences(of: isError ? "Error: " : "Warning: ", with: "")
                issues.append(parseDoctorTextIssue(issueText, severity: severity))
            } else if let warningRange = text.range(of: "Warning: ") {
                let actualText = String(text[warningRange.lowerBound...])
                let issueText = actualText.replacingOccurrences(of: "Warning: ", with: "")
                issues.append(parseDoctorTextIssue(issueText, severity: .warning))
            }
        }
        
        return issues.sorted { $0.severity > $1.severity }
    }
    
    private func parseDoctorTextIssue(_ text: String, severity: DoctorIssue.Severity) -> DoctorIssue {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let summary = lines.first ?? "Unknown issue"
        let details = lines.dropFirst().joined(separator: "\n")
        
        var fixCommand: [String]? = nil
        for line in lines {
            if line.hasPrefix("brew ") {
                let parts = line.components(separatedBy: " ")
                fixCommand = Array(parts.dropFirst())
            }
        }
        return DoctorIssue(severity: severity, summary: summary, details: details, fixCommand: fixCommand)
    }

    public func parseConfig(_ output: String) -> [BrewConfigSection] {
        var sections: [BrewConfigSection] = []
        let lines = output.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let title = parts[0].trimmingCharacters(in: .whitespaces)
                let content = parts[1].trimmingCharacters(in: .whitespaces)
                sections.append(BrewConfigSection(title: title, content: content))
            } else if let last = sections.last {
                // `brew config` emits occasional bare continuation lines (build
                // details, warnings) — fold them into the previous entry rather
                // than spawning a pile of identical "Other" rows.
                sections[sections.count - 1] = BrewConfigSection(
                    title: last.title,
                    content: last.content.isEmpty ? trimmed : last.content + "\n" + trimmed
                )
            }
        }
        
        return sections
    }

    public func parseServices(_ jsonString: String) throws -> [BrewServiceStatus] {
        guard let data = jsonString.data(using: .utf8) else {
            throw BrewBarError.parseError("Invalid UTF-8 string")
        }
        let decoder = JSONDecoder()
        let entries = try decoder.decode([BrewServiceEntry].self, from: data)
        return entries.map {
            BrewServiceStatus(name: $0.name, status: $0.status, user: $0.user, plist: $0.file)
        }
    }

    public func parseInstalledPackages(_ jsonString: String) throws -> [FormulaItem] {
        guard let data = jsonString.data(using: .utf8) else {
            throw BrewBarError.parseError("Invalid UTF-8 string")
        }
        let decoder = JSONDecoder()
        let output = try decoder.decode(BrewListOutput.self, from: data)

        var items: [FormulaItem] = []

        for formula in output.formulae {
            // Prefer the keg record: it carries the real installed version and
            // install time. `installed_versions` is a fallback for older brew.
            let keg = formula.installed?.first
            let version = keg?.version ?? formula.installed_versions?.first ?? formula.current_version ?? "unknown"
            let installedDate = keg?.time.map { Date(timeIntervalSince1970: $0) }
            let dependencies = (formula.dependencies ?? []) + (formula.uses_from_macos ?? [])
            items.append(FormulaItem(
                id: formula.name,
                name: formula.name,
                fullTitle: formula.full_name ?? formula.name,
                description: formula.desc ?? "",
                currentVersion: version,
                latestVersion: formula.current_version,
                type: .formula,
                homepage: formula.homepage,
                license: formula.license,
                installedDate: installedDate,
                lastChecked: Date(),
                isPinned: formula.pinned ?? false,
                dependencies: dependencies.map { Dependency(name: $0) }
            ))
        }

        for cask in output.casks {
            // `brew info --json=v2 --installed` has no `installed_versions` for
            // casks — the installed spec lives in `installed` (a string that may
            // carry a ",build" suffix) and the tap's latest in `version`.
            let version = cask.installed ?? cask.installed_versions?.first ?? cask.current_version ?? "unknown"
            let installedDate = cask.installed_time.map { Date(timeIntervalSince1970: $0) }
            let name = cask.name?.first ?? cask.token
            items.append(FormulaItem(
                id: cask.token,
                name: name,
                fullTitle: cask.token,
                description: cask.desc ?? "",
                currentVersion: version,
                latestVersion: cask.version,
                type: .cask,
                homepage: cask.homepage,
                installedDate: installedDate,
                lastChecked: Date(),
                isPinned: cask.pinned ?? false
            ))
        }

        return items
    }

    public func parseOutdatedPackages(_ jsonString: String) throws -> (formulas: [BrewFormula], casks: [BrewOutdatedCask]) {
        guard let data = jsonString.data(using: .utf8) else {
            throw BrewBarError.parseError("Invalid UTF-8 string")
        }
        let decoder = JSONDecoder()
        let output = try decoder.decode(BrewOutdatedOutput.self, from: data)
        return (output.formulae, output.casks)
    }
}
