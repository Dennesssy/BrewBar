# BrewBar

A native macOS GUI for [Homebrew](https://brew.sh), built with Swift 6 and SwiftUI.

## Features

- **Dynamic Package Icons**: Automatically generates high-quality app icons using GitHub avatars and Favicons on the fly.
- **Rich GitHub Integration**: Package detail pages fetch live GitHub Stars and full `README.md` documentation.
- **Brew Doctor Diagnostics**: 1-click health diagnostics to keep your system clean and functional.
- **Dead Package Filtering**: Aggressively filters out deprecated and disabled packages so you only see healthy software.
- **Updates & Management**: Browse, search, install, upgrade, and cleanly remove formulas and casks.
- **Semantic Search**: Fast fuzzy matching over installed and Spotlight-indexed packages.

## Requirements

- macOS 14+
- Swift 6 toolchain (Xcode 16+)
- [Homebrew](https://brew.sh) installed at `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel)

## Building

```bash
swift build
```
