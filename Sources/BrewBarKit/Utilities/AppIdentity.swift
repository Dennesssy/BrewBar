// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation

/// One place for identifiers that must stay stable across the app bundle,
/// Keychain, Spotlight, logs, and the on-disk cache.
public enum AppIdentity {
    public static let bundleIdentifier = "com.dennisstewart.brewbar"
    public static let logSubsystem = bundleIdentifier
    public static let cacheDirectoryName = bundleIdentifier
    public static let spotlightDomain = bundleIdentifier + ".packages"
    public static let githubKeychainService = bundleIdentifier + ".github"
}
