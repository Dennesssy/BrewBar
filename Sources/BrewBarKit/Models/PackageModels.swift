import Foundation

public enum PackageType: String, Codable, Sendable, CaseIterable, Identifiable {
    case formula
    case cask
    case tap

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .formula: return "Formula"
        case .cask: return "Cask"
        case .tap: return "Tap"
        }
    }
}

public enum PackageStatus: String, Codable, Sendable, CaseIterable {
    case active
    case maintained
    case archived
    case deprecated
}

public struct Dependency: Codable, Sendable, Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let isOptional: Bool
    public let isBuildOnly: Bool
    public let dependencies: [Dependency]

    public init(name: String, isOptional: Bool = false, isBuildOnly: Bool = false, dependencies: [Dependency] = []) {
        self.name = name
        self.isOptional = isOptional
        self.isBuildOnly = isBuildOnly
        self.dependencies = dependencies
    }
}

public struct PackageVersion: Codable, Sendable, Identifiable, Hashable {
    public var id: String { version }
    public let version: String
    public let releaseDate: Date?
    public let changelog: String?
    public let isCurrent: Bool

    public init(version: String, releaseDate: Date? = nil, changelog: String? = nil, isCurrent: Bool = false) {
        self.version = version
        self.releaseDate = releaseDate
        self.changelog = changelog
        self.isCurrent = isCurrent
    }
}

public struct BrewServiceStatus: Codable, Sendable, Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let status: String // e.g. "started", "stopped", "error"
    public let user: String?
    public let plist: String?

    public init(name: String, status: String, user: String? = nil, plist: String? = nil) {
        self.name = name
        self.status = status
        self.user = user
        self.plist = plist
    }
}

public struct FormulaItem: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let fullTitle: String?
    public let description: String
    public let currentVersion: String
    public let latestVersion: String?
    public let type: PackageType
    public let homepage: String?
    public let repository: String?
    public let license: String?
    public let sizeInBytes: UInt64?
    public let installedDate: Date?
    public let lastChecked: Date?
    public let updateAvailable: Bool
    public let isPinned: Bool
    public let isAutoUpdateEnabled: Bool
    public let dependencies: [Dependency]
    public let versions: [PackageVersion]
    /// True for results sourced from GitHub repository search rather than a
    /// verified Homebrew formula/cask — a repo tagged `homebrew-formula` is
    /// not guaranteed to be `brew install`-able under that name. Views
    /// should not offer a direct Install action for these.
    public let isRemoteSuggestion: Bool

    public init(
        id: String,
        name: String,
        fullTitle: String? = nil,
        description: String = "",
        currentVersion: String = "",
        latestVersion: String? = nil,
        type: PackageType = .formula,
        homepage: String? = nil,
        repository: String? = nil,
        license: String? = nil,
        sizeInBytes: UInt64? = nil,
        installedDate: Date? = nil,
        lastChecked: Date? = nil,
        updateAvailable: Bool = false,
        isPinned: Bool = false,
        isAutoUpdateEnabled: Bool = false,
        dependencies: [Dependency] = [],
        versions: [PackageVersion] = [],
        isRemoteSuggestion: Bool = false
    ) {
        self.id = id
        self.name = name
        self.fullTitle = fullTitle
        self.description = description
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.type = type
        self.homepage = homepage
        self.repository = repository
        self.license = license
        self.sizeInBytes = sizeInBytes
        self.installedDate = installedDate
        self.lastChecked = lastChecked
        self.updateAvailable = updateAvailable
        self.isPinned = isPinned
        self.isAutoUpdateEnabled = isAutoUpdateEnabled
        self.dependencies = dependencies
        self.versions = versions
        self.isRemoteSuggestion = isRemoteSuggestion
    }
}
