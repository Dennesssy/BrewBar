import Foundation
import SwiftData

@Model
public final class HistoryRecord {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var packageName: String
    public var packageType: String
    public var action: String // "install", "upgrade", "uninstall"
    public var version: String?
    public var details: String?
    
    public init(id: UUID = UUID(), timestamp: Date = Date(), packageName: String, packageType: String, action: String, version: String? = nil, details: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.packageName = packageName
        self.packageType = packageType
        self.action = action
        self.version = version
        self.details = details
    }
}
