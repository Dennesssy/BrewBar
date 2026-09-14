#!/bin/bash

# 1. Fix Keychain spam (Bug 10)
sed -i '' 's/if status == errSecItemNotFound {/if status == errSecItemNotFound { return nil }/g' Sources/BrewBarKit/Persistence/Persistence.swift

# 2. Add Clear History (Bug 8 / Feedback 3)
sed -i '' '/public func log(/i\
    public func clearAll() {\
        let context = container.mainContext\
        try? context.delete(model: HistoryRecord.self)\
        try? context.save()\
    }\
' Sources/BrewBarKit/Persistence/HistoryStore.swift

# 3. Add Clear Button to HistoryView
sed -i '' '/.navigationTitle("History")/a\
        .toolbar {\
            ToolbarItem(placement: .primaryAction) {\
                Button(role: .destructive) {\
                    HistoryStore.shared.clearAll()\
                } label: {\
                    Label("Clear History", systemImage: "trash")\
                }\
            }\
        }\
' Sources/BrewBarApp/Views/HistoryView.swift

# 4. Debounce Search (Bug 1)
# Note: AppSearchState is in ViewModels.swift
# We'll just add a Task.sleep to performSearch
sed -i '' '/public func performSearch() async {/a\
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce\
        if Task.isCancelled { return }\
' Sources/BrewBarKit/ViewModels/ViewModels.swift

# 5. Add Brewfile Export & Cleanup (Feedback 1 & 4)
# In BrewService.swift
cat << 'INJECT' >> Sources/BrewBarKit/Services/BrewService.swift

    public func cleanup() async throws -> String {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let builder = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).cleanup()
        return try await processManager.execute(executablePath: builder.executablePath, arguments: builder.buildArguments())
    }

    public func doctor() async throws -> String {
        let prefs = await LocalStorageManager.shared.loadPreferences()
        return try await processManager.execute(executablePath: prefs.homebrewPrefix, arguments: ["doctor"])
    }
INJECT

# Add builder command
cat << 'INJECT' >> Sources/BrewBarKit/Utilities/BrewCommandBuilder.swift

    public func cleanup() -> Self {
        arguments.append("cleanup")
        return self
    }
INJECT

