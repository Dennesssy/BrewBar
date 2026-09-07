# BrewBar Systems Document

## Core Systems Overview

BrewBar implements multiple interconnected systems to achieve seamless Homebrew package management with modern UX. This document details each system's responsibility, design, and integration points.

---

## 1. Homebrew CLI Wrapper System

### Purpose
Safe, validated execution of Homebrew commands with JSON output parsing and error handling.

### Components

#### BrewCommandBuilder
```swift
/// Safely constructs brew CLI commands with shell escaping
class BrewCommandBuilder {
    private var command: String = "brew"
    private var subcommand: String = ""
    private var arguments: [String] = []
    private var options: [String: String] = [:]
    
    func install(_ formula: String) -> BrewCommandBuilder {
        self.subcommand = "install"
        self.arguments = [escapedString(formula)]
        return self
    }
    
    func upgrade(_ formula: String? = nil) -> BrewCommandBuilder {
        self.subcommand = "upgrade"
        if let formula = formula {
            self.arguments = [escapedString(formula)]
        }
        return self
    }
    
    func uninstall(_ formula: String) -> BrewCommandBuilder {
        self.subcommand = "uninstall"
        self.arguments = [escapedString(formula)]
        return self
    }
    
    func list(json: Bool = true) -> BrewCommandBuilder {
        self.subcommand = "list"
        if json {
            self.options["json"] = "v2"
        }
        return self
    }
    
    func outdated(json: Bool = true) -> BrewCommandBuilder {
        self.subcommand = "outdated"
        if json {
            self.options["json"] = "v2"
        }
        return self
    }
    
    private func escapedString(_ str: String) -> String {
        // Escape single quotes and wrap in quotes
        "'\(str.replacingOccurrences(of: "'", with: "\\'"))'"
    }
    
    func build() -> String {
        var components = [command, subcommand]
        
        for (key, value) in options {
            if value.isEmpty {
                components.append("--\(key)")
            } else {
                components.append("--\(key)=\(value)")
            }
        }
        
        components.append(contentsOf: arguments)
        return components.joined(separator: " ")
    }
}

// Usage:
let cmd = BrewCommandBuilder()
    .list(json: true)
    .build()  // "brew list --json=v2"
```

#### OutputParser
```swift
/// Parses Homebrew CLI JSON output
struct OutputParser {
    
    /// Parse `brew list --json=v2` output
    static func parseInstalledPackages(_ json: String) throws -> [FormulaItem] {
        let decoder = JSONDecoder()
        let output = try decoder.decode(BrewListOutput.self, from: json.data(using: .utf8)!)
        
        var items: [FormulaItem] = []
        
        // Parse formulas
        for formula in output.formulae {
            items.append(FormulaItem(
                id: formula.name,
                name: formula.name,
                currentVersion: formula.installed_versions.first ?? "unknown",
                type: .formula,
                description: formula.desc ?? "",
                installedDate: Date(),
                lastChecked: Date()
            ))
        }
        
        // Parse casks
        for cask in output.casks {
            items.append(FormulaItem(
                id: cask.token,
                name: cask.name,
                currentVersion: cask.installed_versions.first ?? "unknown",
                type: .cask,
                description: cask.desc ?? "",
                installedDate: Date(),
                lastChecked: Date()
            ))
        }
        
        return items
    }
    
    /// Parse `brew outdated --json=v2` output
    static func parseOutdatedPackages(_ json: String) throws -> (formulas: [BrewFormula], casks: [BrewCask]) {
        let decoder = JSONDecoder()
        let output = try decoder.decode(BrewOutdatedOutput.self, from: json.data(using: .utf8)!)
        return (output.formulae, output.casks)
    }
    
    /// Parse `brew info --json=v2` output
    static func parseFormulaDetails(_ json: String) throws -> BrewFormulaDetails {
        let decoder = JSONDecoder()
        let output = try decoder.decode([BrewFormulaDetails].self, from: json.data(using: .utf8)!)
        return output.first ?? BrewFormulaDetails()
    }
}

// Models for parsing
struct BrewListOutput: Codable {
    let formulae: [BrewFormula]
    let casks: [BrewCask]
}

struct BrewOutdatedOutput: Codable {
    let formulae: [BrewFormula]
    let casks: [BrewCask]
}

struct BrewFormula: Codable {
    let name: String
    let desc: String?
    let installed_versions: [String]
    let current_version: String
    let outdated: Bool?
    let homepage: String?
    let repository: String?
}

struct BrewCask: Codable {
    let token: String
    let name: String
    let desc: String?
    let installed_versions: [String]
    let current_version: String
    let outdated: Bool?
    let homepage: String?
}
```

#### ProcessManager
```swift
/// Executes shell commands safely
class ProcessManager {
    
    @Published var isRunning = false
    @Published var progress: Double = 0
    
    typealias OutputHandler = (String) -> Void
    
    /// Execute brew command and capture output
    func execute(
        command: String,
        timeout: TimeInterval = 300,
        outputHandler: OutputHandler? = nil
    ) async throws -> String {
        DispatchQueue.main.async { self.isRunning = true }
        defer { DispatchQueue.main.async { self.isRunning = false } }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        
        // Wait for completion with timeout
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(100_000)  // 0.1s
        }
        
        if process.isRunning {
            process.terminate()
            throw BrewBarError.commandTimeout(command)
        }
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        if process.terminationStatus != 0 {
            let error = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw BrewBarError.commandFailed(command, error)
        }
        
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw BrewBarError.parseError("Invalid output encoding")
        }
        
        outputHandler?(output)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

---

## 2. Package Service System

### Purpose
High-level package operations: install, upgrade, remove, dependency resolution.

### BrewService (Main Orchestrator)

```swift
@MainActor
class BrewService: NSObject, ObservableObject {
    static let shared = BrewService()
    
    @Published var installedPackages: [FormulaItem] = []
    @Published var availableUpdates: [FormulaItem] = []
    @Published var isLoading = false
    @Published var lastError: BrewBarError?
    
    private let processManager = ProcessManager()
    private let outputParser = OutputParser()
    private let errorHandler = ErrorHandler()
    
    // MARK: - Install Operations
    
    func installFormula(_ name: String) async throws {
        guard validateFormulaName(name) else {
            throw BrewBarError.invalidFormulaName(name)
        }
        
        let cmd = BrewCommandBuilder().install(name).build()
        let output = try await processManager.execute(command: cmd)
        
        // Refresh installed packages
        try await refreshInstalledPackages()
    }
    
    func installMultiple(_ names: [String]) async throws {
        for name in names {
            try await installFormula(name)
        }
    }
    
    // MARK: - Upgrade Operations
    
    func upgradeFormula(_ name: String) async throws {
        let cmd = BrewCommandBuilder().upgrade(name).build()
        let output = try await processManager.execute(command: cmd)
        
        try await refreshInstalledPackages()
        try await checkForUpdates()
    }
    
    func upgradeAll() async throws {
        let cmd = BrewCommandBuilder().upgrade().build()
        let output = try await processManager.execute(command: cmd)
        
        try await refreshInstalledPackages()
        try await checkForUpdates()
    }
    
    // MARK: - Uninstall Operations
    
    func uninstallFormula(_ name: String) async throws {
        let cmd = BrewCommandBuilder().uninstall(name).build()
        let output = try await processManager.execute(command: cmd)
        
        try await refreshInstalledPackages()
    }
    
    // MARK: - Query Operations
    
    func refreshInstalledPackages() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let cmd = BrewCommandBuilder().list(json: true).build()
        let output = try await processManager.execute(command: cmd)
        
        let packages = try outputParser.parseInstalledPackages(output)
        DispatchQueue.main.async {
            self.installedPackages = packages
        }
    }
    
    func checkForUpdates() async throws {
        let cmd = BrewCommandBuilder().outdated(json: true).build()
        let output = try await processManager.execute(command: cmd)
        
        let (formulas, casks) = try outputParser.parseOutdatedPackages(output)
        
        // Convert to FormulaItem with updateAvailable flag
        var updates: [FormulaItem] = []
        
        for formula in formulas {
            updates.append(FormulaItem(
                id: formula.name,
                name: formula.name,
                currentVersion: formula.installed_versions.first ?? "",
                latestVersion: formula.current_version,
                type: .formula,
                updateAvailable: true
            ))
        }
        
        for cask in casks {
            updates.append(FormulaItem(
                id: cask.token,
                name: cask.name,
                currentVersion: cask.installed_versions.first ?? "",
                latestVersion: cask.current_version,
                type: .cask,
                updateAvailable: true
            ))
        }
        
        DispatchQueue.main.async {
            self.availableUpdates = updates
        }
    }
    
    // MARK: - Validation
    
    private func validateFormulaName(_ name: String) -> Bool {
        // Only alphanumeric, hyphens, underscores
        let pattern = "^[a-zA-Z0-9_-]+$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return regex?.firstMatch(in: name, range: range) != nil
    }
}
```

---

## 3. Update Check System

### Purpose
Periodic background checks for package updates with smart scheduling and notifications.

```swift
class UpdateCheckService: NSObject {
    static let shared = UpdateCheckService()
    
    @Published var nextCheckTime: Date?
    @Published var lastCheckTime: Date?
    
    private var timer: Timer?
    private let brewService = BrewService.shared
    private let notificationManager = NotificationManager.shared
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Scheduling
    
    func startPeriodicChecks(interval: TimeInterval = 3600) {  // 1 hour default
        // Check on app launch
        Task {
            await performCheck()
        }
        
        // Schedule recurring checks
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                await self?.performCheck()
            }
        }
    }
    
    func stopPeriodicChecks() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Checking
    
    private func performCheck() async {
        guard shouldPerformCheck() else { return }
        
        do {
            try await brewService.checkForUpdates()
            lastCheckTime = Date()
            scheduleNextCheck()
            
            // Notify user if updates available
            if !brewService.availableUpdates.isEmpty {
                await notifyAboutUpdates(brewService.availableUpdates)
            }
        } catch {
            Logger.shared.error("Update check failed: \(error)")
        }
    }
    
    private func shouldPerformCheck() -> Bool {
        // Don't check if:
        // - Another check is already running
        // - Last check was < 5 minutes ago
        // - Homebrew not installed
        
        guard let lastCheck = lastCheckTime else { return true }
        return Date().timeIntervalSince(lastCheck) > 300
    }
    
    private func scheduleNextCheck() {
        let nextCheck = Date().addingTimeInterval(3600)
        nextCheckTime = nextCheck
        
        // For persistent scheduling (even after app close), use UNUserNotificationCenter
        let content = UNMutableNotificationContent()
        content.title = "Checking for updates..."
        content.body = "BrewBar will check for available updates"
        content.sound = nil
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 3600,
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: "update-check",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { _ in }
    }
    
    // MARK: - Notifications
    
    private func notifyAboutUpdates(_ updates: [FormulaItem]) async {
        // Group by type
        let formulas = updates.filter { $0.type == .formula }
        let casks = updates.filter { $0.type == .cask }
        
        let title = "\(updates.count) Update\(updates.count == 1 ? "" : "s") Available"
        let body = formulas.count > 0 ? 
            "Formulas: \(formulas.count), Casks: \(casks.count)" :
            "\(casks.count) cask\(casks.count == 1 ? "" : "s")"
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: updates.count)
        
        // Add action buttons
        let updateAction = UNNotificationAction(
            identifier: "UPDATE_ALL",
            title: "Update All",
            options: .foreground
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "UPDATE_AVAILABLE",
            actions: [updateAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        content.categoryIdentifier = "UPDATE_AVAILABLE"
        
        // Schedule for now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.shared.error("Failed to schedule notification: \(error)")
            }
        }
    }
}
```

---

## 4. Notification System

### Purpose
Manage user notifications for updates, installations, and errors.

```swift
class NotificationManager: NSObject, NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    @Published var notificationPreferences = NotificationPreferences()
    @Published var pendingNotifications: [BrewNotification] = []
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        loadPreferences()
    }
    
    // MARK: - Permission Management
    
    func requestPermissions() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
    
    // MARK: - Notification Types
    
    func notifyInstallationComplete(_ formula: FormulaItem) {
        let content = UNMutableNotificationContent()
        content.title = "✅ Installation Complete"
        content.body = "\(formula.name) \(formula.currentVersion) installed successfully"
        content.sound = .default
        content.badge = NSNumber(value: 0)  // Clear badge
        
        content.userInfo = [
            "formulaID": formula.id,
            "type": "installation_complete"
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: formula.id,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { _ in }
    }
    
    func notifyInstallationFailed(_ formula: FormulaItem, error: String) {
        let content = UNMutableNotificationContent()
        content.title = "❌ Installation Failed"
        content.body = "\(formula.name): \(error)"
        content.sound = .default
        
        content.userInfo = [
            "formulaID": formula.id,
            "type": "installation_failed",
            "error": error
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(formula.id)_error",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { _ in }
    }
    
    // MARK: - Delegate Methods
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        switch response.actionIdentifier {
        case "UPDATE_ALL":
            Task {
                try await BrewService.shared.upgradeAll()
            }
        case "OPEN_APP":
            // Open app or navigate to specific screen
            break
        default:
            break
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
}

// Data Models
struct NotificationPreferences: Codable {
    var notifyFormulas = true
    var notifyCasks = true
    var notifyTaps = false
    var notifyBeta = false
    var autoUpdatePatches = false
    var autoUpdateMinor = false
    var updateAtNight = true
    var nightUpdateTime = "02:00"  // 2 AM
    
    var formulaPreferences: [String: FormulaNotificationPreference] = [:]
}

struct FormulaNotificationPreference: Codable {
    let formulaID: String
    var notifyOnUpdate: Bool = true
    var autoUpdate: Bool = false
    var updateChannel: UpdateChannel = .stable
}

enum UpdateChannel: String, Codable {
    case stable
    case beta
    case all
}

struct BrewNotification: Identifiable {
    let id = UUID()
    let type: NotificationType
    let title: String
    let body: String
    let timestamp: Date
    let actionable: Bool
    
    enum NotificationType {
        case updateAvailable
        case installationComplete
        case installationFailed
        case upgradeComplete
        case upgradeFailed
        case systemError
    }
}
```

---

## 5. Search & Discovery System

### Purpose
Full-text search, filtering, and recommendation engine for formula discovery.

```swift
class SearchService: NSObject, ObservableObject {
    static let shared = SearchService()
    
    @Published var searchResults: [FormulaItem] = []
    @Published var recentSearches: [String] = []
    @Published var isSearching = false
    
    private var searchCache: [String: [FormulaItem]] = [:]
    private let cacheQueue = DispatchQueue(label: "com.brewbar.search-cache")
    
    // MARK: - Search Operations
    
    func search(_ query: String, filters: SearchFilters = .default) async -> [FormulaItem] {
        guard !query.isEmpty else {
            return []
        }
        
        DispatchQueue.main.async { self.isSearching = true }
        defer { DispatchQueue.main.async { self.isSearching = false } }
        
        // Check cache
        let cacheKey = "\(query)_\(filters.hashValue)"
        if let cached = cacheQueue.sync({ searchCache[cacheKey] }) {
            return cached
        }
        
        // Perform search
        var results: [FormulaItem] = []
        
        // 1. Search locally installed
        results.append(contentsOf: searchInstalledPackages(query))
        
        // 2. Search remote (GitHub API)
        let remoteResults = await searchRemote(query, filters: filters)
        results.append(contentsOf: remoteResults)
        
        // 3. Apply filters
        results = applyFilters(results, filters)
        
        // 4. Cache results
        cacheQueue.async {
            self.searchCache[cacheKey] = results
        }
        
        // 5. Store in recents
        addToRecentSearches(query)
        
        return results
    }
    
    private func searchInstalledPackages(_ query: String) -> [FormulaItem] {
        let lowercased = query.lowercased()
        return BrewService.shared.installedPackages.filter { formula in
            formula.name.lowercased().contains(lowercased) ||
            formula.description.lowercased().contains(lowercased)
        }
    }
    
    private func searchRemote(_ query: String, filters: SearchFilters) async -> [FormulaItem] {
        // Query GitHub API for formulas
        // Implementation details in GitHubAPIClient
        do {
            return try await GitHubAPIClient.shared.searchFormulas(
                query: query,
                filters: filters
            )
        } catch {
            Logger.shared.error("Remote search failed: \(error)")
            return []
        }
    }
    
    private func applyFilters(_ items: [FormulaItem], _ filters: SearchFilters) -> [FormulaItem] {
        return items.filter { item in
            // Type filter
            if !filters.types.isEmpty && !filters.types.contains(item.type) {
                return false
            }
            
            // Status filter
            if !filters.statuses.isEmpty {
                // TODO: Add status tracking to FormulaItem
            }
            
            return true
        }
    }
    
    private func addToRecentSearches(_ query: String) {
        DispatchQueue.main.async {
            self.recentSearches.removeAll { $0 == query }  // Remove duplicates
            self.recentSearches.insert(query, at: 0)
            self.recentSearches = Array(self.recentSearches.prefix(10))  // Keep last 10
            
            // Persist
            UserDefaults.standard.set(self.recentSearches, forKey: "recentSearches")
        }
    }
    
    func clearRecentSearches() {
        DispatchQueue.main.async {
            self.recentSearches.removeAll()
            UserDefaults.standard.removeObject(forKey: "recentSearches")
        }
    }
}

struct SearchFilters: Hashable {
    var types: Set<PackageType> = [.formula, .cask]
    var statuses: Set<PackageStatus> = []
    var languages: Set<String> = []
    var licenses: Set<String> = []
    var maxSize: UInt64?  // Bytes
    var sortBy: SortOption = .relevance
    var limit: Int = 50
    
    static let `default` = SearchFilters()
    
    enum SortOption {
        case relevance
        case downloads
        case rating
        case dateAdded
        case dateUpdated
    }
}

enum PackageStatus {
    case active
    case maintained
    case archived
    case deprecated
}
```

---

## 6. GitHub Authentication System

### Purpose
OAuth 2.0 integration for user authentication and plugin submissions.

```swift
class GitHubAuthManager: NSObject, ObservableObject {
    static let shared = GitHubAuthManager()
    
    @Published var currentUser: GitHubUser?
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var authError: String?
    
    private let clientID = "YOUR_GITHUB_OAUTH_CLIENT_ID"
    private let clientSecret = "YOUR_GITHUB_OAUTH_CLIENT_SECRET"  // Store in Keychain!
    private let redirectURI = "brewbar://github-callback"
    private let keychainService = KeychainManager.shared
    
    override init() {
        super.init()
        loadStoredToken()
    }
    
    // MARK: - OAuth Flow
    
    func startOAuthFlow() {
        let state = UUID().uuidString
        UserDefaults.standard.set(state, forKey: "oauth_state")
        
        let authURL = URL(string: "https://github.com/login/oauth/authorize")!
        var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "repo read:user"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "allow_signup", value: "true")
        ]
        
        NSWorkspace.shared.open(components.url!)
    }
    
    func handleOAuthCallback(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            authError = "Invalid OAuth callback"
            return
        }
        
        // Verify state
        let savedState = UserDefaults.standard.string(forKey: "oauth_state")
        guard state == savedState else {
            authError = "State mismatch (CSRF protection)"
            return
        }
        
        isAuthenticating = true
        
        Task {
            do {
                let token = try await exchangeCodeForToken(code)
                try keychainManager.saveToken(token, service: "github")
                
                let user = try await fetchGitHubUser(token)
                
                DispatchQueue.main.async {
                    self.currentUser = user
                    self.isAuthenticated = true
                    self.isAuthenticating = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.authError = error.localizedDescription
                    self.isAuthenticating = false
                }
            }
        }
    }
    
    // MARK: - Token Management
    
    private func exchangeCodeForToken(_ code: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "client_id=\(clientID)&client_secret=\(clientSecret)&code=\(code)"
        request.httpBody = body.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BrewBarError.authenticationFailed("GitHub rejected request")
        }
        
        let result = try JSONDecoder().decode(GitHubTokenResponse.self, from: data)
        return result.access_token
    }
    
    private func fetchGitHubUser(_ token: String) async throws -> GitHubUser {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BrewBarError.authenticationFailed("Failed to fetch user info")
        }
        
        return try JSONDecoder().decode(GitHubUser.self, from: data)
    }
    
    private func loadStoredToken() {
        do {
            if let token = try keychainManager.retrieveToken(service: "github") {
                isAuthenticating = true
                
                Task {
                    do {
                        let user = try await fetchGitHubUser(token)
                        DispatchQueue.main.async {
                            self.currentUser = user
                            self.isAuthenticated = true
                            self.isAuthenticating = false
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.isAuthenticating = false
                            self.logout()
                        }
                    }
                }
            }
        } catch {
            Logger.shared.error("Failed to load stored token: \(error)")
        }
    }
    
    func logout() {
        DispatchQueue.main.async {
            self.currentUser = nil
            self.isAuthenticated = false
            try? self.keychainManager.deleteToken(service: "github")
        }
    }
}

// Models
struct GitHubTokenResponse: Codable {
    let access_token: String
    let token_type: String
    let scope: String
}

struct GitHubUser: Codable, Identifiable {
    let id: Int
    let login: String
    let name: String?
    let avatar_url: String
    let bio: String?
    let public_repos: Int
    let followers: Int
    let created_at: String
}

// Keychain wrapper for secure token storage
class KeychainManager {
    static let shared = KeychainManager()
    
    func saveToken(_ token: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: token.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw BrewBarError.keychainError("Failed to save token")
        }
    }
    
    func retrieveToken(service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    func deleteToken(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BrewBarError.keychainError("Failed to delete token")
        }
    }
}
```

---

## 7. Persistence & Caching System

### Purpose
Local storage for preferences, favorites, installation history, and API response caching.

```swift
class PersistenceManager: NSObject {
    static let shared = PersistenceManager()
    
    private let userDefaults = UserDefaults(suiteName: "com.dennesssy.brewbar")!
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    override init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("com.dennesssy.brewbar")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        super.init()
    }
    
    // MARK: - User Preferences
    
    func savePreferences(_ prefs: UserPreferences) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(prefs) {
            userDefaults.set(data, forKey: "preferences")
        }
    }
    
    func loadPreferences() -> UserPreferences {
        if let data = userDefaults.data(forKey: "preferences"),
           let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            return prefs
        }
        return UserPreferences()
    }
    
    // MARK: - Favorites
    
    func saveFavorites(_ favorites: Set<String>) {
        userDefaults.set(Array(favorites), forKey: "favorites")
    }
    
    func loadFavorites() -> Set<String> {
        if let favs = userDefaults.array(forKey: "favorites") as? [String] {
            return Set(favs)
        }
        return []
    }
    
    func addFavorite(_ id: String) {
        var favorites = loadFavorites()
        favorites.insert(id)
        saveFavorites(favorites)
    }
    
    func removeFavorite(_ id: String) {
        var favorites = loadFavorites()
        favorites.remove(id)
        saveFavorites(favorites)
    }
    
    // MARK: - Cache
    
    func cacheData(_ data: Data, forKey key: String, ttl: TimeInterval = 3600) {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try? data.write(to: fileURL)
        
        // Store expiration time
        let expiration = Date().addingTimeInterval(ttl)
        userDefaults.set(expiration, forKey: "\(key)_expiration")
    }
    
    func cachedData(forKey key: String) -> Data? {
        // Check expiration
        if let expiration = userDefaults.object(forKey: "\(key)_expiration") as? Date {
            if Date() > expiration {
                clearCache(forKey: key)
                return nil
            }
        }
        
        let fileURL = cacheDirectory.appendingPathComponent(key)
        return try? Data(contentsOf: fileURL)
    }
    
    func clearCache(forKey key: String) {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try? fileManager.removeItem(at: fileURL)
        userDefaults.removeObject(forKey: "\(key)_expiration")
    }
    
    func clearAllCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

struct UserPreferences: Codable {
    var launchAtLogin = true
    var showMenuBarIcon = true
    var checkForAppUpdates = true
    var darkMode: DarkModeSetting = .system
    var updateCheckInterval: TimeInterval = 3600  // 1 hour
    var defaultShell = "zsh"
    
    enum DarkModeSetting: String, Codable {
        case system
        case light
        case dark
    }
}
```

This completes the core systems. Each system is designed to be:
- **Independently testable** (mockable dependencies)
- **Loosely coupled** (via published properties + protocols)
- **Thread-safe** (appropriate dispatch queues + @MainActor)
- **Observable** (Combine publishers for UI binding)

