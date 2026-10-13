# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Added
- Accounts tab: read-only CLI status view for GitHub, Google Cloud, AWS, npm, Vercel, Netlify, Wrangler, Firebase, and 1Password, plus local credential file hygiene checks.
- Package Detail view now includes a Pin / Unpin button for installed formulas.
- Security tab: `brew vulns --json` results grouped by severity, packages that could not be checked, per-package upgrade, optional CISA known-exploited badges and read-only checks of this Mac. Lookups send package names and versions to OSV.dev, so they are off until enabled (new `allowVulnerabilityLookups` preference, default off).
- Unit tests for the new brew operations, doctor/config parsing and the vulnerability parser (suite is now 13 tests).
- Live task console with the exact command, streamed output and a Cancel button.
- Doctor screen (`brew doctor --json`, text fallback) and Configuration screen (`brew config`).
- Services actions run through the shared progress pipeline and History; Restart offered for failed services; Show Log when `brew services info` reports a log path.
- Preview before uninstall and before Update All.
- Added tap/untap, pin/unpin, autoremove, reinstall, link/unlink and bundle commands to `BrewCommandBuilder`.
- Sidebar shortcuts ⌘1–⌘9; About moved to the app menu.

### Changed
- Removed a `/bin/bash` shell call when fetching the `--help` manual page, instead resolving the executable path directly.
- Read-only brew queries run with `HOMEBREW_NO_AUTO_UPDATE=1`.
- README no longer claims sandboxing, shell-injection immunity, Secure Enclave storage or macOS 27 / HIG 2026 support.

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
