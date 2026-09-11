import Foundation

public enum BrewBarError: LocalizedError, Sendable, Equatable {
    case formulaNotFound(String)
    case installationFailed(String)
    case commandFailed(command: String, error: String)
    case commandTimeout(String)
    case invalidFormulaName(String)
    case parseError(String)
    case authenticationFailed(String)
    case keychainError(String)
    case networkError(String)
    case homebrewNotInstalled

    public var errorDescription: String? {
        switch self {
        case .formulaNotFound(let name):
            return "Formula or cask '\(name)' was not found."
        case .installationFailed(let reason):
            return "Installation failed: \(reason)"
        case .commandFailed(let cmd, let error):
            return "Command '\(cmd)' failed: \(error)"
        case .commandTimeout(let cmd):
            return "Command '\(cmd)' timed out."
        case .invalidFormulaName(let name):
            return "Invalid package name: '\(name)'."
        case .parseError(let msg):
            return "Failed to parse Homebrew output: \(msg)"
        case .authenticationFailed(let msg):
            return "Authentication failed: \(msg)"
        case .keychainError(let msg):
            return "Keychain error: \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .homebrewNotInstalled:
            return "Homebrew is not installed or not found at configured path."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .formulaNotFound:
            return "Check the spelling or search for similar package names."
        case .installationFailed, .commandFailed:
            return "Check your internet connection and permissions or inspect terminal logs."
        case .homebrewNotInstalled:
            return "Install Homebrew from https://brew.sh or set the correct Homebrew prefix in Preferences."
        default:
            return "Try the operation again or check system settings."
        }
    }
}

public struct ErrorHandler: Sendable {
    public init() {}

    public func handle(_ error: Error) -> BrewBarError {
        if let brewError = error as? BrewBarError {
            return brewError
        }
        return .networkError(error.localizedDescription)
    }
}
