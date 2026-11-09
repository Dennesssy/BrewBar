// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation
#if canImport(AppKit)
import AppKit

/// Resolves a cask to its installed `.app` so installed packages can offer
/// the same "Open" action the App Store shows for purchased apps.
@MainActor
public final class AppLauncher {
    public static let shared = AppLauncher()

    private var appsByNormalizedName: [String: URL] = [:]
    private var didScan = false

    public init() {}

    public func appURL(for item: FormulaItem) -> URL? {
        // Only casks ship a launchable .app; matching a formula name against
        // /Applications would produce coincidental "Open" buttons.
        guard item.type == .cask else { return nil }
        scanIfNeeded()
        for candidate in [item.id, item.name, item.fullTitle ?? ""] where !candidate.isEmpty {
            if let url = appsByNormalizedName[Self.normalize(candidate)] {
                return url
            }
        }
        return nil
    }

    public func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Casks installed while the app is running shouldn't wait for a relaunch
    /// before "Open" appears.
    public func rescan() {
        didScan = false
        appsByNormalizedName = [:]
        scanIfNeeded()
    }

    private func scanIfNeeded() {
        guard !didScan else { return }
        didScan = true

        let fileManager = FileManager.default
        let directories = ["/Applications", NSHomeDirectory() + "/Applications"]

        for directory in directories {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: directory),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension == "app" {
                appsByNormalizedName[Self.normalize(url.deletingPathExtension().lastPathComponent)] = url

                if let bundle = Bundle(url: url) {
                    if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                        appsByNormalizedName[Self.normalize(displayName)] = url
                    }
                    if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                        appsByNormalizedName[Self.normalize(bundleName)] = url
                    }
                }
            }
        }
    }

    nonisolated static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
#endif
