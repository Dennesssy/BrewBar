# BrewBar

A native macOS GUI for [Homebrew](https://brew.sh), built with Swift 6 and SwiftUI.

## Features

- Browse, search, and install formulas and casks
- View and apply available updates, individually or all at once
- Sort and filter installed packages (by name, install date, size, or pending updates)
- Semantic search with fuzzy matching over installed and Spotlight-indexed packages
- Package details, dependencies, and version history
- Configurable Homebrew path (auto-detected per architecture: Apple Silicon vs Intel)

## Requirements

- macOS 14+
- Swift 6 toolchain (Xcode 16+)
- [Homebrew](https://brew.sh) installed at `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel)

## Project layout

```
Sources/
  BrewBarKit/        Core library: models, services, persistence, networking, utilities, view models
  BrewBarApp/         SwiftUI app target: views and app entry point
Tests/
  BrewBarTests/       Unit tests for BrewBarKit
```

`BrewBarKit` is a standalone library target with no UI dependencies, so its services
(`BrewService`, `SearchService`, `CacheManager`, etc.) can be tested independently of SwiftUI.

## Building

```bash
swift build
```

## Running tests

```bash
swift test
```

## Architecture notes

- **Process execution**: `ProcessManager` runs `brew` directly via `Process` with an
  explicit executable path and argument array — it does not shell out through
  `/bin/bash -c`, so user-controlled input (formula names, the configured Homebrew
  path) cannot be interpreted as shell syntax.
- **Concurrency**: The package builds under Swift 6 strict concurrency
  (`StrictConcurrency` upcoming feature). Shared mutable state crossing
  actor/closure boundaries (e.g. process output buffers) is wrapped in
  `@unchecked Sendable` boxes guarded by `NSLock`.
- **Caching**: `CacheManager` encodes cache keys as URL-safe Base64 before turning
  them into filenames, avoiding both key collisions and path traversal.

## Contributing

See [CHANGELOG.md](CHANGELOG.md) for recent changes. Pull requests are reviewed
with an automated Macroscope code review in addition to manual review.
