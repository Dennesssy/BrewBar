// Copyright © 2026 Dennis Stewart. All rights reserved.

import Foundation
import Combine

public struct CLIStatus: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let state: State
    public let account: String?
    public let commandUsed: String?

    public enum State: Sendable {
        case loggedIn, notLoggedIn, unknown, notInstalled
    }

    public var stateString: String {
        switch state {
        case .loggedIn: return "Logged in"
        case .notLoggedIn: return "Not logged in"
        case .unknown: return "Unknown"
        case .notInstalled: return "Not installed"
        }
    }

}

public struct HygieneIssue: Identifiable, Sendable {
    public let id = UUID()
    public let path: String
    public let permissions: Int16

    public var permissionsString: String {
        return String(format: "0o%03o", permissions)
    }
    
    public static func isFlagged(permissions: Int16) -> Bool {
        return permissions & 0o077 != 0
    }
}

@MainActor
public final class AccountsViewModel: ObservableObject {
    @Published public private(set) var cliStatuses: [CLIStatus] = []
    @Published public private(set) var hygieneIssues: [HygieneIssue] = []
    @Published public private(set) var isLoading = false
    
    @Published public private(set) var activeGhAccount: String?
    @Published public private(set) var activeGcloudAccount: String?

    private let processManager = ProcessManager()

    public init() {}

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        
        async let ghRes = checkGH()
        async let gcloudRes = checkGcloud()
        async let awsRes = checkAws()
        async let npmRes = checkNpm()
        async let vercelRes = checkVercel()
        async let netlifyRes = checkNetlify()
        async let wranglerRes = checkWrangler()
        async let firebaseRes = checkFirebase()
        async let opRes = checkOp()

        let statuses = await [ghRes, gcloudRes, awsRes, npmRes, vercelRes, netlifyRes, wranglerRes, firebaseRes, opRes]
        self.cliStatuses = statuses.compactMap { $0 }
        
        self.activeGhAccount = self.cliStatuses.first { $0.name == "gh" && $0.state == .loggedIn }?.account
        self.activeGcloudAccount = self.cliStatuses.first { $0.name == "gcloud" && $0.state == .loggedIn }?.account

        await checkHygiene()
    }
    
    private func findExecutable(_ name: String) -> String? {
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        for path in paths {
            let checkPath = (path as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: checkPath) {
                return checkPath
            }
        }
        return nil
    }

    private func executeSafeCommand(executable: String, arguments: [String]) async -> String? {
        do {
            let output = try await processManager.execute(executablePath: executable, arguments: arguments, timeout: 10)
            return redactOutput(output)
        } catch {
            return nil
        }
    }

    public func redactOutput(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        
        // Use regex for word boundaries to avoid matching "keyring" for "key"
        let keywordsPattern = "\\b(token|secret|password|key)\\b"
        let regex = try? NSRegularExpression(pattern: keywordsPattern, options: .caseInsensitive)
        
        let safeLines = lines.filter { line in
            let lower = line.lowercased()
            if let regex = regex {
                let range = NSRange(location: 0, length: lower.utf16.count)
                if regex.firstMatch(in: lower, options: [], range: range) != nil {
                    return false
                }
            }
            
            // Check for base64-like long string (rudimentary check: > 40 chars and no spaces)
            // Allow token characters: _, -, =, +, /
            let tokenChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-=+/"))
            let words = line.components(separatedBy: .whitespaces)
            for word in words {
                if word.count > 40 && word.rangeOfCharacter(from: tokenChars.inverted) == nil {
                    return false
                }
            }
            return true
        }
        return safeLines.joined(separator: "\n")
    }

    public func parseGHStatus(output: String, command: String) -> CLIStatus {
        let accountLines = output.components(separatedBy: .newlines).filter { $0.contains("Logged in to") }
        if !accountLines.isEmpty {
            let account = accountLines.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CLIStatus(name: "gh", state: .loggedIn, account: account, commandUsed: command)
        }
        
        if output.contains("You are not logged into any GitHub hosts") {
            return CLIStatus(name: "gh", state: .notLoggedIn, account: nil, commandUsed: command)
        }
        
        return CLIStatus(name: "gh", state: .unknown, account: nil, commandUsed: command)
    }

    private func checkGH() async -> CLIStatus? {
        guard let path = findExecutable("gh") else {
            return nil
        }
        let args = ["auth", "status"]
        let command = "gh auth status"
        guard let output = await executeSafeCommand(executable: path, arguments: args) else {
            return CLIStatus(name: "gh", state: .unknown, account: nil, commandUsed: command)
        }
        
        return parseGHStatus(output: output, command: command)
    }

    public func parseGcloudStatus(output: String, command: String) -> CLIStatus {
        let activeLine = output.components(separatedBy: .newlines).first { $0.contains("ACTIVE") }
        if let line = activeLine {
            let parts = line.components(separatedBy: .whitespaces)
            let account = parts.first
            return CLIStatus(name: "gcloud", state: .loggedIn, account: account, commandUsed: command)
        }
        return CLIStatus(name: "gcloud", state: .notLoggedIn, account: nil, commandUsed: command)
    }

    private func checkGcloud() async -> CLIStatus? {
        guard let path = findExecutable("gcloud") else {
            return nil
        }
        let args = ["auth", "list", "--format=value(account,status)"]
        let command = "gcloud auth list --format=value(account,status)"
        guard let output = await executeSafeCommand(executable: path, arguments: args) else {
            return CLIStatus(name: "gcloud", state: .unknown, account: nil, commandUsed: command)
        }
        
        return parseGcloudStatus(output: output, command: command)
    }

    private func checkAws() async -> CLIStatus? {
        guard let path = findExecutable("aws") else {
            return nil
        }
        let args = ["configure", "list-profiles"]
        let command = "aws configure list-profiles"
        guard let output = await executeSafeCommand(executable: path, arguments: args) else {
            return CLIStatus(name: "aws", state: .unknown, account: nil, commandUsed: command)
        }
        let profiles = output.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !profiles.isEmpty {
            return CLIStatus(name: "aws", state: .loggedIn, account: profiles.joined(separator: ", "), commandUsed: command)
        }
        return CLIStatus(name: "aws", state: .notLoggedIn, account: nil, commandUsed: command)
    }

    private func checkNpm() async -> CLIStatus? {
        guard let path = findExecutable("npm") else {
            return nil
        }
        let args = ["whoami"]
        let command = "npm whoami"
        guard let output = await executeSafeCommand(executable: path, arguments: args) else {
            return CLIStatus(name: "npm", state: .unknown, account: "not logged in or unreachable", commandUsed: command)
        }
        let account = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !account.isEmpty && !account.contains("ENEEDAUTH") {
            return CLIStatus(name: "npm", state: .loggedIn, account: account, commandUsed: command)
        }
        return CLIStatus(name: "npm", state: .notLoggedIn, account: nil, commandUsed: command)
    }
    
    private func checkVercel() async -> CLIStatus? {
        guard let path = findExecutable("vercel") else { return nil }
        let args = ["whoami"]
        let command = "vercel whoami"
        guard let output = await executeSafeCommand(executable: path, arguments: args) else {
            return CLIStatus(name: "vercel", state: .unknown, account: nil, commandUsed: command)
        }
        let account = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.contains("Error!") {
            return CLIStatus(name: "vercel", state: .notLoggedIn, account: nil, commandUsed: command)
        } else if !account.isEmpty {
            return CLIStatus(name: "vercel", state: .loggedIn, account: account, commandUsed: command)
        }
        return CLIStatus(name: "vercel", state: .unknown, account: nil, commandUsed: command)
    }
    
    private func checkNetlify() async -> CLIStatus? {
        guard let path = findExecutable("netlify") else { return nil }
        let args = ["status"]
        let command = "netlify status"
        guard let output = await executeSafeCommand(executable: path, arguments: args) else {
            return CLIStatus(name: "netlify", state: .unknown, account: nil, commandUsed: command)
        }
        if let line = output.components(separatedBy: .newlines).first(where: { $0.contains("Email:") || $0.contains("Name:") }) {
            return CLIStatus(name: "netlify", state: .loggedIn, account: line.trimmingCharacters(in: .whitespaces), commandUsed: command)
        }
        return CLIStatus(name: "netlify", state: .notLoggedIn, account: nil, commandUsed: command)
    }
    
    private func checkWrangler() async -> CLIStatus? {
        guard let path = findExecutable("wrangler") else { return nil }
        let args = ["whoami"]
        let command = "wrangler whoami"
        guard let output = await executeSafeCommand(executable: path, arguments: args) else {
            return CLIStatus(name: "wrangler", state: .unknown, account: nil, commandUsed: command)
        }
        if output.contains("You are not authenticated") {
            return CLIStatus(name: "wrangler", state: .notLoggedIn, account: nil, commandUsed: command)
        } else if let line = output.components(separatedBy: .newlines).first(where: { $0.contains("Logged in with") || $0.contains("Account Name") }) {
            return CLIStatus(name: "wrangler", state: .loggedIn, account: line.trimmingCharacters(in: .whitespaces), commandUsed: command)
        }
        return CLIStatus(name: "wrangler", state: .unknown, account: nil, commandUsed: command)
    }
    
    private func checkFirebase() async -> CLIStatus? {
        guard let path = findExecutable("firebase") else { return nil }
        let args = ["login:list"]
        let command = "firebase login:list"
        guard let output = await executeSafeCommand(executable: path, arguments: args) else {
            return CLIStatus(name: "firebase", state: .unknown, account: nil, commandUsed: command)
        }
        let lines = output.components(separatedBy: .newlines).filter { $0.contains("@") && !$0.contains("No authorized accounts") }
        if !lines.isEmpty {
            return CLIStatus(name: "firebase", state: .loggedIn, account: lines.joined(separator: ", "), commandUsed: command)
        }
        return CLIStatus(name: "firebase", state: .notLoggedIn, account: nil, commandUsed: command)
    }

    private func checkOp() async -> CLIStatus? {
        guard let path = findExecutable("op") else { return nil }
        let args = ["account", "list"]
        let command = "op account list"
        guard let output = await executeSafeCommand(executable: path, arguments: args) else {
            return CLIStatus(name: "1Password", state: .unknown, account: nil, commandUsed: command)
        }
        let accounts = output.components(separatedBy: .newlines).filter { $0.contains("http") || $0.contains("@") }
        if !accounts.isEmpty {
            return CLIStatus(name: "1Password", state: .loggedIn, account: accounts.first?.trimmingCharacters(in: .whitespaces), commandUsed: command)
        }
        return CLIStatus(name: "1Password", state: .notLoggedIn, account: nil, commandUsed: command)
    }

    private func checkHygiene() async {
        let home = NSHomeDirectory()
        let pathsToCheck = [
            "\(home)/.netrc",
            "\(home)/.npmrc",
            "\(home)/.docker/config.json",
            "\(home)/.aws/credentials",
            "\(home)/.config/gh/hosts.yml"
        ]
        
        var issues: [HygieneIssue] = []
        let fm = FileManager.default
        
        // Also check any file matching *token*, *credentials*, *auth* in home (shallow check)
        var allPaths = pathsToCheck
        if let homeFiles = try? fm.contentsOfDirectory(atPath: home) {
            for file in homeFiles {
                let lower = file.lowercased()
                if lower.contains("token") || lower.contains("credentials") || lower.contains("auth") {
                    allPaths.append("\(home)/\(file)")
                }
            }
        }
        
        for path in Set(allPaths) {
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let posix = attrs[.posixPermissions] as? NSNumber {
                let mode = posix.int16Value
                if HygieneIssue.isFlagged(permissions: mode) {
                    issues.append(HygieneIssue(path: path, permissions: mode))
                }
            }
        }
        
        self.hygieneIssues = issues.sorted { $0.path < $1.path }
    }
}
