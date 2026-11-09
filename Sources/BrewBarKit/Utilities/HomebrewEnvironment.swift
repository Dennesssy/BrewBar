// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// Answers "is Homebrew actually usable right now?" once per launch so the
/// UI can show a setup screen instead of a wall of failed `brew` commands.
@MainActor
public final class HomebrewEnvironment: ObservableObject {
    public static let shared = HomebrewEnvironment()

    public enum Status: Equatable, Sendable {
        case checking
        case available(executablePath: String)
        case missing(detectedPath: String?)
    }

    @Published public private(set) var status: Status = .checking

    public init() {}

    public var isAvailable: Bool {
        if case .available = status { return true }
        return false
    }

    public func refresh() async {
        status = .checking
        let prefs = await LocalStorageManager.shared.loadPreferences()
        let executable = BrewCommandBuilder(brewPath: prefs.homebrewPrefix).executablePath

        if FileManager.default.isExecutableFile(atPath: executable) {
            status = .available(executablePath: executable)
            return
        }

        status = .missing(detectedPath: HomebrewPath.locateInstalled())
    }

    /// Adopts a Homebrew install found in a standard location without making
    /// the user type a path into Preferences first.
    public func adoptDetectedPath() async {
        guard case .missing(let detected?) = status else { return }
        await setPath(detected)
    }

    public func setPath(_ path: String) async {
        var prefs = await LocalStorageManager.shared.loadPreferences()
        prefs.homebrewPrefix = path
        await LocalStorageManager.shared.savePreferences(prefs)
        await refresh()
    }
}
