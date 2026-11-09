// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// Architecture-aware default path for the Homebrew executable.
/// Apple Silicon installs to `/opt/homebrew`, Intel installs to `/usr/local`.
public enum HomebrewPath {
    public static let defaultBrewExecutable: String = {
        #if arch(arm64)
        return "/opt/homebrew/bin/brew"
        #else
        return "/usr/local/bin/brew"
        #endif
    }()

    /// Standard install locations, checked in order. Used when the configured
    /// path is wrong but Homebrew is present somewhere else (e.g. Rosetta).
    public static func locateInstalled() -> String? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
            NSHomeDirectory() + "/.linuxbrew/bin/brew",
            "/home/linuxbrew/.linuxbrew/bin/brew"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
