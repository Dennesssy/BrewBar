// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

public struct Vulnerability: Codable, Sendable, Identifiable {
    public let id = UUID()
    public let cve: String
    public let summary: String
    public let severity: String
    public let fixedIn: String?
    
    // Derived property for sorting
    public var severityScore: Int {
        switch severity.lowercased() {
        case "critical": return 4
        case "high": return 3
        case "medium": return 2
        case "low": return 1
        default: return 0
        }
    }
}

public struct VulnerablePackage: Codable, Sendable, Identifiable {
    public let id = UUID()
    public let package: String
    public let version: String
    public let vulnerabilities: [Vulnerability]
    public let isExploited: Bool
    
    public init(package: String, version: String, vulnerabilities: [Vulnerability], isExploited: Bool = false) {
        self.package = package
        self.version = version
        self.vulnerabilities = vulnerabilities
        self.isExploited = isExploited
    }
}

public struct SkippedPackage: Codable, Sendable, Identifiable {
    public let id = UUID()
    public let package: String
    public let reason: String
}

public struct VulnsScanResult: Codable, Sendable {
    public let vulnerablePackages: [VulnerablePackage]
    public let skippedPackages: [SkippedPackage]
    public let isOlderHomebrew: Bool
}
