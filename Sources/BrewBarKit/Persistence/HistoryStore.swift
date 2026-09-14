import Foundation
import SwiftData

@MainActor
public struct HistoryStore {
    public static let shared = HistoryStore()
    public let container: ModelContainer
    
    public init() {
        do {
            container = try ModelContainer(for: HistoryRecord.self)
        } catch {
            fatalError("Failed to create SwiftData container for HistoryRecord: \(error)")
        }
    }
    
    public func log(packageName: String, packageType: String, action: String, version: String? = nil, details: String? = nil) {
        let context = ModelContext(container)
        let record = HistoryRecord(packageName: packageName, packageType: packageType, action: action, version: version, details: details)
        context.insert(record)
        try? context.save()
    }
}
