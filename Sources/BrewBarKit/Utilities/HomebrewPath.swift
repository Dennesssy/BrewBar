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
}
