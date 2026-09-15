# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Fixed
- **Security**: `ProcessManager` now executes `brew` via an explicit executable
  path and argument array instead of `/bin/bash -c`, removing the shell-injection
  surface by construction rather than relying solely on input filtering.
- Cask upgrades/installs/uninstalls (e.g. Google Chrome) now use the package's
  brew token (`item.id`) instead of its human-readable display name
  (`item.name`), which brew could not resolve.
- `InstalledViewModel` sort options `Installed (Newest)`, `Installed (Oldest)`,
  and `Size (Largest)` now actually sort the list instead of being no-ops.
- `CacheManager` cache keys are now URL-safe Base64 encoded, fixing a key
  collision (`formula/foo` and `formula_foo` previously mapped to the same
  file) and a path-traversal bug (`clearCache(forKey: "..")` could delete the
  entire Caches directory).
- `GitHubAPIClient.searchFormulas` now builds its request URL with
  `URLComponents`/`URLQueryItem` instead of manual percent-encoding, so search
  queries containing `&` are no longer truncated.
- `HomeView` now triggers `checkForUpdates()` on appear, so the updates banner
  is populated on first launch instead of staying empty until the user visits
  the Updates tab.
- `UpdatesViewModel.checkForUpdates()` now clears `availableUpdates` when the
  underlying check fails, instead of silently leaving stale entries visible.
- `BrewService.checkForUpdates()` now reconciles `updateAvailable` back into
  `installedPackages`, so the "only updates" filter returns results.
- Default `homebrewPrefix` is now architecture-aware (`/opt/homebrew` on Apple
  Silicon, `/usr/local` on Intel) via a new `HomebrewPath` helper, instead of
  hardcoding the Apple Silicon path.
- `ProcessManager` now drains stdout/stderr pipes to EOF after process
  termination instead of relying solely on the last `readabilityHandler`
  callback, preventing truncated JSON output from `brew --json` commands.
- Fixed a Swift 6 strict-concurrency build failure in `ProcessManager`
  (mutation of captured vars / non-Sendable closure capture across the
  process's output-reading closures) that prevented the package from
  compiling at all.

## Initial implementation

- Scaffolded `BrewBar` native macOS application in Swift 6, targeting macOS 14
  with strict concurrency, as `BrewBarApp` (executable) and `BrewBarKit`
  (library).
- SwiftUI entry point, sidebar navigation, and Home/Installed/Updates/Search/
  Details/Preferences views.
- `BrewBarKit` models for packages, user preferences, application state, and
  plugin submissions.
- Homebrew integration via `BrewService`/`ProcessManager`, local persistence
  via `LocalStorageManager`/`KeychainManager`, and search via
  `GitHubAPIClient`/`SemanticSearchEngine`.
- CoreSpotlight indexing of installed packages and a semantic search engine
  with alias mapping, intent classification, and fuzzy matching.
- `CacheManager` with TTL expiration and atomic writes.
- Unit tests for command building, parsing, and search ranking.
