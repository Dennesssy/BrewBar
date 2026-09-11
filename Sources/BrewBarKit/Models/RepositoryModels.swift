import Foundation

public struct PluginManifest: Codable, Sendable, Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let version: String
    public let description: String
    public let author: String
    public let homepage: String?
    public let permissions: [String]

    public init(name: String, version: String, description: String, author: String, homepage: String? = nil, permissions: [String] = []) {
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.homepage = homepage
        self.permissions = permissions
    }
}

public struct PluginVersion: Codable, Sendable, Identifiable, Hashable {
    public var id: String { version }
    public let version: String
    public let checksum: String
    public let releaseNotes: String?
    public let downloadUrl: String

    public init(version: String, checksum: String, releaseNotes: String? = nil, downloadUrl: String) {
        self.version = version
        self.checksum = checksum
        self.releaseNotes = releaseNotes
        self.downloadUrl = downloadUrl
    }
}

public struct PluginSubmission: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let manifest: PluginManifest
    public let versions: [PluginVersion]
    public let submissionDate: Date
    public let isApproved: Bool

    public init(id: String = UUID().uuidString, manifest: PluginManifest, versions: [PluginVersion] = [], submissionDate: Date = Date(), isApproved: Bool = false) {
        self.id = id
        self.manifest = manifest
        self.versions = versions
        self.submissionDate = submissionDate
        self.isApproved = isApproved
    }
}
