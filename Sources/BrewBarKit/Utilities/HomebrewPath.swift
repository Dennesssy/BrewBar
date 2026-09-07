import Foundation

/// Provides architecture-aware default paths for Homebrew.
///
/// Homebrew installs to different locations depending on the processor architecture:
/// - Apple Silicon (arm64): `/opt/homebrew/bin/brew`
/// - Intel (x86_64): `/usr/local/bin/brew`
public enum HomebrewPath {
    /// The default Homebrew executable path for the current architecture.
    #if arch(arm64)
    public static let defaultBrewExecutable = "/opt/homebrew/bin/brew"
    #else
    public static let defaultBrewExecutable = "/usr/local/bin/brew"
    #endif

    /// Path to the Homebrew executable on Apple Silicon Macs.
    public static let appleSiliconBrewPath = "/opt/homebrew/bin/brew"

    /// Path to the Homebrew executable on Intel Macs.
    public static let intelBrewPath = "/usr/local/bin/brew"
}
