// Copyright © 2026 Dennis Stewart. All rights reserved.

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
            // A corrupted on-disk store must not crash the app — fall back to
            // an in-memory container so history just doesn't persist.
            Logger.shared.error("HistoryStore: falling back to in-memory container: \(error)")
            container = try! ModelContainer(
                for: HistoryRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }
    
    public func clearAll() {
        let context = container.mainContext
        try? context.delete(model: HistoryRecord.self)
        try? context.save()
    }

    public func log(packageName: String, packageType: String, action: String, version: String? = nil, details: String? = nil) {
        let context = container.mainContext
        let record = HistoryRecord(packageName: packageName, packageType: packageType, action: action, version: version, details: details)
        context.insert(record)
        try? context.save()
    }
}
