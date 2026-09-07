import Foundation

public enum InstallationPhase: String, Codable, Sendable {
    case idle
    case resolvingDependencies
    case downloading
    case installing
    case testing
    case completed
    case failed
}

public struct InstallationState: Codable, Sendable, Identifiable {
    public var id: String { packageId }
    public let packageId: String
    public let packageName: String
    public var phase: InstallationPhase
    public var progressFraction: Double // 0.0 to 1.0
    public var bytesDownloaded: UInt64
    public var totalBytes: UInt64
    public var currentMessage: String
    public var errorMessage: String?

    public init(
        packageId: String,
        packageName: String,
        phase: InstallationPhase = .idle,
        progressFraction: Double = 0,
        bytesDownloaded: UInt64 = 0,
        totalBytes: UInt64 = 0,
        currentMessage: String = "",
        errorMessage: String? = nil
    ) {
        self.packageId = packageId
        self.packageName = packageName
        self.phase = phase
        self.progressFraction = progressFraction
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.currentMessage = currentMessage
        self.errorMessage = errorMessage
    }
}

public struct NotificationState: Codable, Sendable {
    public var unreadUpdatesCount: Int
    public var lastNotifiedDate: Date?

    public init(unreadUpdatesCount: Int = 0, lastNotifiedDate: Date? = nil) {
        self.unreadUpdatesCount = unreadUpdatesCount
        self.lastNotifiedDate = lastNotifiedDate
    }
}

public enum SortOrderOption: String, Codable, Sendable, CaseIterable, Identifiable {
    case nameAscending = "Name (A-Z)"
    case nameDescending = "Name (Z-A)"
    case installedDateNewest = "Installed (Newest)"
    case installedDateOldest = "Installed (Oldest)"
    case sizeLargest = "Size (Largest)"

    public var id: String { rawValue }
}

public struct FilterState: Codable, Sendable, Hashable {
    public var selectedType: PackageType?
    public var onlyUpdates: Bool
    public var onlyWithDependencies: Bool
    public var searchQuery: String

    public init(selectedType: PackageType? = nil, onlyUpdates: Bool = false, onlyWithDependencies: Bool = false, searchQuery: String = "") {
        self.selectedType = selectedType
        self.onlyUpdates = onlyUpdates
        self.onlyWithDependencies = onlyWithDependencies
        self.searchQuery = searchQuery
    }

    public static let defaultFilters = FilterState()
}
