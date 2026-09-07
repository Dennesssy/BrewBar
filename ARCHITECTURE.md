# BrewBar Architecture

## Overview

BrewBar is a native macOS application that provides an App Store-inspired graphical interface for Homebrew package management. Rather than implementing a custom plugin system, BrewBar wraps Homebrew's CLI and presents a modern, discoverable UI for installing, updating, and managing packages (formulas, casks, and taps).

**Core Philosophy:** Don't reinvent Homebrew. Wrap it elegantly.

---

## System Architecture

```
┌─────────────────────────────────────────────────────┐
│           macOS Monterey+ (SwiftUI)                 │
│         BrewBar Native Application                  │
└──────────────────┬──────────────────────────────────┘
                   │
       ┌───────────┴───────────┐
       │                       │
┌──────▼──────────┐   ┌────────▼─────────┐
│  Local State    │   │  Remote Services │
│   & Caching     │   │                  │
├─────────────────┤   ├──────────────────┤
│ • Installed     │   │ • GitHub API     │
│ • Favorites     │   │   (formulas)     │
│ • Preferences   │   │ • Update Server  │
│ • History       │   │ • Analytics      │
└────────┬────────┘   └────────┬─────────┘
         │                     │
         └──────────┬──────────┘
                    │
        ┌───────────▼────────────┐
        │   Homebrew CLI Wrapper │
        ├────────────────────────┤
        │ • Shell command runner │
        │ • JSON output parser   │
        │ • Process manager      │
        │ • Error handler        │
        └───────────┬────────────┘
                    │
        ┌───────────▼────────────┐
        │  Homebrew Installation │
        │  (/usr/local/bin/brew) │
        ├────────────────────────┤
        │ • Formulas (CLI tools) │
        │ • Casks (GUI apps)     │
        │ • Taps (repos)         │
        │ • Services             │
        └────────────────────────┘
```

---

## Core Layers

### 1. **Presentation Layer (SwiftUI)**

Handles all user-facing interfaces and interactions.

```
UI Views/
├── Home/
│   ├── HomeView
│   ├── UpdatesBannerView
│   ├── FeaturedCarouselView
│   └── RecommendedGridView
├── Installed/
│   ├── InstalledFormulasView
│   ├── InstalledFormulaRowView
│   └── FilterChipsView
├── Updates/
│   ├── UpdatesAvailableView
│   ├── UpdateItemRowView
│   └── UpdateFilterView
├── Search/
│   ├── SearchBrowseView
│   ├── SearchResultsView
│   └── FilterSidebarView
├── Detail/
│   ├── FormulaDetailView
│   ├── VersionHistoryView
│   ├── DependencyGraphView
│   └── ReviewsView
├── Settings/
│   ├── PreferencesView
│   ├── GeneralSettingsView
│   ├── NotificationSettingsView
│   └── AboutView
└── Components/
    ├── PluginRepository View (legacy support)
    └── MenuBar Integration
```

### 2. **State Management Layer (Combine + @State/@StateObject)**

Manages application state, reactive updates, and data flow.

```
ViewModels/
├── HomeViewModel
│   └── Publishes: featured, recommended, trending
├── InstalledViewModel
│   └── Publishes: installedFormulas, filterState, sortOrder
├── UpdatesViewModel
│   └── Publishes: availableUpdates, updateProgress, completedUpdates
├── SearchViewModel
│   └── Publishes: searchResults, filterState, recentSearches
├── FormulaDetailViewModel
│   └── Publishes: formulaDetails, reviews, versions, dependencies
└── PreferencesViewModel
    └── Publishes: userPreferences, notificationSettings
```

### 3. **Domain Models (Core Data Structures)**

```
Models/
├── Package/
│   ├── FormulaItem          (unifies Formula/Cask metadata)
│   ├── BrewService          (service-related info)
│   ├── Dependency           (recursive dependency tree)
│   └── PackageVersion       (version history + changelog)
├── State/
│   ├── InstallationState    (tracking installs/upgrades)
│   ├── NotificationState    (update availability)
│   └── FilterState          (UI filter selections)
├── User/
│   ├── GitHubUser           (authenticated user)
│   ├── UserPreferences      (stored settings)
│   ├── UserReview           (formula review/rating)
│   └── UserFavorite         (bookmarked formulas)
└── Repository/
    ├── PluginSubmission     (for extension marketplace)
    ├── PluginVersion        (versioning + checksums)
    └── PluginManifest       (metadata + permissions)
```

### 4. **Service Layer (Business Logic)**

```
Services/
├── BrewService
│   ├── executeBrewCommand()
│   ├── parseJSONOutput()
│   ├── handleErrors()
│   └── manageProcesses()
├── PackageService
│   ├── getInstalledPackages()
│   ├── checkForUpdates()
│   ├── installPackage()
│   ├── upgradePackage()
│   ├── removePackage()
│   └── resolveDependencies()
├── SearchService
│   ├── searchFormulas()
│   ├── filterResults()
│   ├── cacheResults()
│   └── indexForFullText()
├── UpdateCheckService
│   ├── performBackgroundCheck()
│   ├── schedulePeriodicChecks()
│   ├── notifyAboutUpdates()
│   └── trackUpdateHistory()
├── NotificationManager
│   ├── scheduleUpdateNotification()
│   ├── handleNotificationActions()
│   └── manageNotificationPreferences()
├── GitHubAuthManager
│   ├── startOAuthFlow()
│   ├── handleOAuthCallback()
│   ├── fetchGitHubUser()
│   └── manageTokens()
└── AnalyticsService
    ├── trackUserActions()
    ├── reportUsageMetrics()
    └── sendAnonEventData()
```

### 5. **Data Access Layer (Persistence)**

```
Persistence/
├── LocalStorageManager
│   ├── UserDefaults wrapper
│   ├── Keychain integration
│   ├── File system cache
│   └── JSON serialization
├── DatabaseManager
│   ├── Core Data schemas
│   ├── Migration handlers
│   ├── Query builders
│   └── Transaction management
└── CacheManager
    ├── In-memory cache
    ├── Disk cache (LRU eviction)
    ├── Cache invalidation
    └── Sync with local storage
```

### 6. **Utility & Infrastructure**

```
Utilities/
├── BrewCommandBuilder      (constructs brew CLI commands safely)
├── OutputParser            (JSON/text parsing from brew output)
├── ProcessManager          (executes shell commands safely)
├── ErrorHandler            (standardizes error reporting)
├── Logger                  (structured logging)
└── VersionComparator       (semver parsing + comparison)

Network/
├── HTTPClient              (with retry logic)
├── GithubAPIClient         (formula repository queries)
├── NotaryScannerAPI        (security checks for casks)
└── AnalyticsReporter       (anonymized telemetry)
```

---

## Data Flow Diagrams

### Installation Flow

```
User clicks "Install"
    │
    ▼
┌─────────────────────────────────┐
│ PackageService.install()        │
│ - Validate formula exists       │
│ - Resolve dependencies          │
│ - Create InstallationState      │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ BrewService.executeCommand()    │
│ brew install <formula>          │
│ + capture output stream         │
└────────────┬────────────────────┘
             │
             ├─────► Parse JSON output
             │       Update InstallationState
             │       Publish progress
             │
             ▼
┌─────────────────────────────────┐
│ Post-install validation         │
│ - Verify binary exists          │
│ - Run formula tests (if any)    │
│ - Update cache                  │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Notify UI                       │
│ - Refresh installed list        │
│ - Show completion toast         │
│ - Trigger analytics             │
└─────────────────────────────────┘
```

### Update Check Flow

```
Background Timer (hourly)
    │
    ▼
┌─────────────────────────────────┐
│ UpdateCheckService.check()      │
│ brew outdated --json=v2         │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Parse output                    │
│ Create FormulaItem[] with       │
│ updateAvailable = true          │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Compare with stored preferences │
│ - notifyFormulas?              │
│ - notifyCasks?                 │
│ - notifyTaps?                  │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Notify (if enabled)             │
│ - Post UNUserNotification       │
│ - Add to UpdatesBadge          │
│ - Publish to @Published         │
└─────────────────────────────────┘
```

### Search Flow

```
User types in search box
    │
    ▼ (debounced 0.3s)
┌─────────────────────────────────┐
│ SearchViewModel.search()        │
└────────────┬────────────────────┘
             │
    ┌────────┴────────┐
    │                 │
    ▼                 ▼
Local Cache      Remote API
    │                 │
    ├─► Fast Results  │
    │                 │
    │        ┌────────▼─────────────┐
    │        │ GitHubAPIClient      │
    │        │ .searchFormulas()    │
    │        └────────┬─────────────┘
    │                 │
    │    ┌────────────┴──────────────┐
    │    ▼                           ▼
    │  Cache Results          Merge with Local
    │    │                           │
    └────┴───────────────┬───────────┘
                         │
                         ▼
                  Publish Results
```

---

## Key Design Patterns

### 1. **Service-Oriented Architecture**
- Separation of concerns (UI ≠ Business Logic ≠ Data Access)
- Easy testing via protocol-based mocks
- Dependency injection for services

### 2. **Reactive Programming (Combine)**
- `@Published` properties drive UI updates
- `@StateObject` for ViewModel lifecycle
- `Combine` operators for data transformation

### 3. **Error Handling Strategy**
```swift
enum BrewBarError: LocalizedError {
    case formulaNotFound(String)
    case installationFailed(String)
    case dependencyConflict([String])
    case networkError(URLError)
    case homebrewNotInstalled
    case permissionDenied
    
    var errorDescription: String? { ... }
    var recoverySuggestion: String? { ... }
}
```

### 4. **Caching Strategy**
- **In-Memory Cache**: Frequently accessed formulas (TTL: 5 min)
- **Disk Cache**: Search results, formula metadata (TTL: 1 hour)
- **User Defaults**: Preferences, favorites, history
- **Keychain**: GitHub OAuth tokens

### 5. **Command Safety**
```swift
// Never execute user input directly
let formula = "malicious; rm -rf /"  // DON'T
let command = BrewCommandBuilder.install(formula)
    .escapedString()  // Properly escaped
    .build()

// Result: brew install 'malicious; rm -rf /'
```

---

## Thread Safety & Concurrency

```
Main Thread:     UI updates, user interactions
    │
    ├─► ViewModels (@MainActor)
    │   └─ Combine publishers on main thread
    │
Background:      Heavy lifting
    ├─► BrewService (DispatchQueue.global)
    ├─► NetworkService (URLSession default)
    ├─► SearchIndexing (DispatchQueue.userInitiated)
    └─► UpdateCheckService (DispatchQueue.background)

Synchronization:
├─ @MainActor dispatch for UI updates
├─ Serial queues for file I/O
└─ Combine handles thread-safe publishing
```

---

## Security Architecture

### 1. **Homebrew Integration**
- ✅ No arbitrary code execution from plugins
- ✅ Use official `brew` binary only
- ✅ Validate all brew output (JSON schema)
- ✅ No shell injection vulnerabilities

### 2. **User Authentication**
- ✅ GitHub OAuth (OAuth 2.0 with PKCE)
- ✅ Tokens stored in macOS Keychain
- ✅ Token refresh before expiration
- ✅ No passwords stored locally

### 3. **Code Signing & Notarization**
- ✅ Apple Developer certificate required
- �� Code signed app bundle
- ✅ Notarized with Apple (Gatekeeper bypass)
- ✅ Version pinning of bundled resources

### 4. **Plugin Submission System** (Future)
- ✅ GitHub OAuth verification of author
- ✅ Automated security scanning (static analysis)
- ✅ Manual review queue
- ✅ Code signing requirement
- ✅ Changelog validation

---

## Deployment & Distribution

### Release Channels
1. **Stable**: Thoroughly tested releases (quarterly)
2. **Beta**: New features (monthly), opt-in via preferences
3. **Nightly**: Latest code for testing (daily builds, CI/CD only)

### Delivery Methods
- **Direct Download**: GitHub Releases (signed DMG)
- **Homebrew**: `brew install brewbar` (self-hosted formula)
- **Mac App Store**: Optional (lower distribution friction)
- **Sparkle**: Auto-update framework (for direct downloads)

---

## Performance Targets

| Operation | Target Time | Notes |
|-----------|------------|-------|
| App launch | < 500ms | After first run; includes cache load |
| List installed | < 1s | Parse `brew list --json=v2` |
| Check updates | < 2s | Run `brew outdated --json=v2` |
| Search (local cache) | < 100ms | In-memory cache hit |
| Search (remote) | < 2s | GitHub API roundtrip |
| Install formula | ~ depends | Brew's responsibility, progress tracked |
| Detail view load | < 300ms | Fetch metadata + reviews |

---

## Testing Strategy

```
Unit Tests:
├── ViewModels (isolated from Services)
├── Services (mocked Brew commands)
├── Models (serialization/deserialization)
├── Utilities (command builders, parsers)
└── Coverage target: 70%+

Integration Tests:
├── BrewService with real brew CLI
├── Database persistence
├── GitHub API client
└── Notification system

UI Tests:
├── Home screen navigation
├── Search functionality
├── Install/update workflows
├── Settings persistence
└── Error handling screens

E2E Tests (Manual):
├── Full app lifecycle
├── Real Homebrew operations
├── Network resilience
└── User journeys
```

---

## Observability

### Logging
```swift
Logger(subsystem: "com.dennesssy.brewbar", category: "Services")
    .info("Installing formula: \(formula.name)")
```

### Metrics
- App usage patterns (anonymized)
- Most-installed formulas
- Update check frequency
- Performance metrics

### Error Reporting
- Opt-in crash reports
- Installation failure logs
- GitHub issue templates

---

## Future Extensibility

### Plugin System (Phase 2)
- Marketplace for community-built tools
- GitHub OAuth-based submission
- Automated validation pipeline
- Review queue + moderation

### Configuration Management
- Brewfile generation from installed packages
- Profile sharing between machines
- Cloud sync (future consideration)

### Advanced Features
- Dependency visualization
- Compilation options UI
- Pre/post-install hooks
- Service management integration

---

## File Structure Summary

```
BrewBar/
├── App.swift                           # Entry point, app delegate
│
├── Views/                              # SwiftUI UI layer
│   ├── Home/
│   ├── Installed/
│   ├── Updates/
│   ├── Search/
│   ├── Detail/
│   ├── Settings/
│   └── Components/
│
├── ViewModels/                         # State management
│   ├── HomeViewModel.swift
│   ├── InstalledViewModel.swift
│   ├── UpdatesViewModel.swift
│   ├── SearchViewModel.swift
│   ├── FormulaDetailViewModel.swift
│   └── PreferencesViewModel.swift
│
├── Models/                             # Data structures
│   ├── Package/
│   ├── State/
│   ├── User/
│   └── Repository/
│
├── Services/                           # Business logic
│   ├── BrewService.swift
│   ├── PackageService.swift
│   ├── SearchService.swift
│   ├── UpdateCheckService.swift
│   ├── NotificationManager.swift
│   ├── GitHubAuthManager.swift
│   └── AnalyticsService.swift
│
├── Persistence/                        # Data access
│   ├── LocalStorageManager.swift
│   ├── DatabaseManager.swift
│   └── CacheManager.swift
│
├── Utilities/                          # Helper functions
│   ├── BrewCommandBuilder.swift
│   ├── OutputParser.swift
│   ├── ProcessManager.swift
│   ├── ErrorHandler.swift
│   ├── Logger.swift
│   └── VersionComparator.swift
│
├── Network/                            # API clients
│   ├── HTTPClient.swift
│   ├── GitHubAPIClient.swift
│   ├── NotaryScannerAPI.swift
│   └── AnalyticsReporter.swift
│
├── Resources/                          # Assets
│   ├── Localization/
│   ├── Assets.xcassets/
│   └── Strings.strings
│
└── Tests/                              # Test suite
    ├── ViewModels/
    ├── Services/
    ├── Models/
    ├── Utilities/
    └── Integration/
```

This architecture prioritizes:
- **Separation of Concerns**: Clear layer boundaries
- **Testability**: Mockable services, isolated logic
- **Maintainability**: Organized file structure
- **Scalability**: Room for plugin system, federation
- **Performance**: Caching, threading, async operations
- **Security**: Safe Homebrew CLI wrapping, OAuth auth

---

## Next Steps

1. **Phase 1**: Core UI + Homebrew integration (3-4 weeks)
2. **Phase 2**: Notifications + background updates (1-2 weeks)
3. **Phase 3**: GitHub auth + reviews/ratings (2-3 weeks)
4. **Phase 4**: Plugin marketplace (4-6 weeks)
5. **Phase 5**: Advanced features + optimization (ongoing)
