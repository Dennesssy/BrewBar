# BrewBar Design Document

## UI/UX Design System

### Visual Language

**Target Users:**
- Experienced Homebrew users seeking better UX
- macOS developers managing multiple packages
- System administrators monitoring package updates
- Power users wanting automation & visibility

**Design Philosophy:**
- Familiar (App Store paradigm)
- Clear (hierarchy, contrast, affordances)
- Fast (responsive, minimal latency)
- Trustworthy (transparent operations, reversible actions)

---

## Screen Designs

### 1. Home Screen (Featured/Discover)

**Purpose:** Central hub showing updates, trending packages, and recommendations

**Layout:**
```
┌─────────────────────────────────────────────┐
│  🏠 Home       🔍 Search    📦 Installed    │ ← Tabs
│  🔔 Updates    ⚙️ Settings                  │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  ⬆️ Updates Available                        │
│  ┌───────────────────────────────────────┐  │
│  │ 📦  3 formulas, 2 casks ready to      │  │
│  │     update                            │  │
│  │                               [Update]│  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Featured                                   │
│ ┌─────────────────────────────────────────┐ │
│ │ [Carousel of featured formulas]         │ │
│ │ • Python 3.11                          │ │
│ │ • Docker                               │ │
│ │ • Node.js 20                           │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Recently Updated                           │
│ ┌─────┬──────┬────────────────────────────┐ │
│ │ App │ v    │ Description              │ │
│ ├─────┼──────┼────────────────────────────┤ │
│ │ git │ 2.42 │ Version control system    │ │
│ │ npm │ 10.0 │ JavaScript package mgr   │ │
│ └─────┴──────┴────────────────────────────┘ │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Recommended for You                        │
│ ┌──────────┐ ┌──────────┐ ┌──────────┐    │
│ │  Rust   │ │  MySQL   │ │PostgreSQL│    │
│ │  1.70   │ │  8.0.1   │ │   15.1   │    │
│ │  [+]    │ │  [+]     │ │  [+]     │    │
│ └──────────┘ └──────────┘ └──────────┘    │
└─────────────────────────────────────────────┘
```

**Key Interactions:**
- [Update All] → Install all available updates
- [Review] → Go to Updates tab (filtered view)
- Carousel → Swipe/click for more featured items
- App cards → Open detail view

---

### 2. Installed Screen (My Packages)

**Purpose:** See all installed formulas/casks with quick actions

**Layout:**
```
┌─────────────────────────────────────────────┐
│  📦 Installed  [Sort: Name ▼] [Filter 🔻]  │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Formulas (12)                              │
│  ┌─────────────────────────────────────────┐│
│  │ git                          v2.42.1   ││
│  │ Distributed version control             ││
│  │ Installed: 3 months ago                 ││
│  │ Size: 52 MB     [⋯ menu]                ││
│  └─────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────┐│
│  │ python                  ⬆️ v3.11 → v3.12││
│  │ Interpreted programming language        ││
│  │ Installed: 2 months ago                 ││
│  │ [Update]  [⋯ menu]                     ││
│  └─────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────┐│
│  │ node                              v20.5  ││
│  │ JavaScript runtime                      ││
│  │ Installed: 1 week ago                   ││
│  │ Size: 89 MB     [⋯ menu]                ││
│  └─────────────────────────────────────────┘│
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Casks (5)                                  │
│  ┌─────────────────────────────────────────┐│
│  │ 🍎 Google Chrome                v120   ││
│  │ Web browser                             ││
│  │ Installed: 2 weeks ago                  ││
│  │ [⋯ menu]                               ││
│  └─────────────────────────────────────────┘│
└─────────────────────────────────────────────┘
```

**Sort Options:**
- Name (A→Z)
- Installed Date (Newest)
- Last Updated
- Size (Largest)

**Filter Chips:**
- All / Formulas / Casks / Taps
- Has Updates
- With Dependencies
- Recently Used

**Context Menu (⋯):**
- Open in Finder
- Open Homepage
- Copy to Clipboard
- View Dependencies
- Run in Terminal
- Uninstall
- Copy command

---

### 3. Updates Screen (Available Updates)

**Purpose:** Focused view of packages needing updates

**Layout:**
```
┌─────────────────────────────────────────────┐
│  ⬆️ Updates                                  │
│  [All ▼] [Formulas] [Casks] [Taps]         │ ← Filters
│  ┌──────────────────────┐  [Settings 🔧]   │
│  │Auto-update patches ✓ │                  │
│  │Auto-update minor ✗  │                  │
│  │Notify on beta ✗     │                  │
│  └──────────────────────┘                  │
└─────────────────────────────────────────────┘

┌────────────────────────��────────────────────┐
│  Formulas (3 updates)                       │
│  ┌─────────────────────────────────────────┐│
│  │ git                                     ││
│  │ v2.41.0 ➜ v2.42.1                      ││
│  │ [Update] [Details]                     ││
│  └─────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────┐│
│  │ python                                  ││
│  │ v3.11.2 ➜ v3.11.5 (patch)               ││
│  │ [Update] [Details]                     ││
│  └─────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────┐│
│  │ openssl@3                               ││
│  │ v3.0.7 ➜ v3.1.0 (major)   ⚠️  Breaking ││
│  │ [Update] [Details] [Changelog]         ││
│  └─────────────────────────────────────────┘│
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Casks (2 updates)                          │
│  ┌─────────────────────────────────────────┐│
│  │ google-chrome                           ││
│  │ v120.0.6099 ➜ v120.0.6099.129           ││
│  │ [Update] [Details]                     ││
│  └─────────────────────────────────────────┘│
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  [Update Selected] (checkbox multi-select)  │
│  [Update All]                               │
└─────────────────────────────────────────────┘
```

**Update Status During Operation:**
```
┌─────────────────────────────────────────────┐
│  🔄 Installing python 3.11.5...             │
│  ┌─────────────────────────────────────────┐│
│  │ ████████████░░░░░░░░░░░░░░ 45%         ││
│  │ Downloading: 34.2 MB / 89.5 MB         ││
│  │ Speed: 2.4 MB/s                         ││
│  │ Time remaining: ~23 seconds             ││
│  └─────────────────────────────────────────┘│
│  [Cancel]                                   │
└─────────────────────────────────────────────┘
```

---

### 4. Search/Browse Screen

**Purpose:** Discover and search for new packages

**Layout:**
```
┌─────────────────────────────────────────────┐
│  🔍 [Search formulas...]          [Advanced▼]
└─────────────────────────────────────────────┘

┌──────────────────┐  ┌───────────────────────┐
│ Categories       │  │ Search Results (42)  │
├──────────────────┤  ├───────────────────────┤
│ Development  ✓   │  │ ┌──────────────────┐ │
│ System           │  │ │ python            │ │
│ Databases        │  │ │ ⭐ 4.8 (256)     │ │
│ Productivity     │  │ │ Popular language │ │
│ DevOps           │  │ │ [Install]        │ │
│ Monitoring       │  │ │ [Details]        │ │
│ Utilities        │  │ └──────────────────┘ │
│                  │  │ ┌──────────────────┐ │
│ [Clear]          │  │ │ pipenv            │ │
└──────────────────┘  │ │ ⭐ 4.5 (128)     │ │
                      │ │ Python envs      │ │
                      │ │ [Install]        │ │
                      │ │ [Details]        │ │
                      │ └──────────────────┘ │
                      │ [Load more...]       │
                      └───────────────────────┘
```

**Advanced Search:**
```
┌─────────────────────────────────────────────┐
│ Filters:                                    │
│ Type: [Formula ▼] [Cask ▼] [Tap ▼]        │
│ Language: [Python ▼] [Ruby ▼] [Go ▼]      │
│ Status: [Active ▼] [Maintained ▼]         │
│ License: [MIT ▼] [Apache ▼] [GPL ▼]       │
│ Size: [< 50 MB ▼]                         │
│                                             │
│ [Search] [Clear]                          │
└─────────────────────────────────────────────┘
```

---

### 5. Detail Screen (Formula/Cask Details)

**Purpose:** Comprehensive information about a package

**Layout:**
```
┌─────────────────────────────────────────────┐
│ ◀ python                              3.11.5│
│                                             │
│ 🐍 Python 3.11.5                           │
│ ⭐ 4.8 (1,342 reviews)                     │
│ Installed: 2 months ago                    │
│ Updated: 1 week ago                        │
│                                             │
│ [Install] [Uninstall] [Update to 3.12]    │
│ [Share] [Add to Favorites] [⋯]             │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ Description                                 │
│                                             │
│ Python is a high-level, interpreted        │
│ programming language known for its         │
│ simplicity and readability. Widely used    │
│ in data science, web development, and      │
│ automation.                                │
│                                             │
│ Homepage: https://www.python.org           │
│ Repository: github.com/Homebrew/...       │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ Information                                 │
├─────────────────────────────────────────────┤
│ Type: Formula                               │
│ Version: 3.11.5                             │
│ Released: Nov 15, 2023                     │
│ Size: 89.5 MB                              │
│ Downloads: 2.4M this month                 │
│ License: PSF (Python Software Foundation) │
│ Maintainer: @homebrew                     │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ Dependencies (4)                            │
│ ├─ openssl@3                                │
│ ├─ sqlite                                   │
│ ├─ readline                                 │
│ └─ ncurses (optional)                       │
│                                             │
│ [Visualize Dependency Graph]               │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ Version History                             │
│ ┌─────────────────────────────────────────┐ │
│ │ v3.11.5  (current) - Nov 15, 2023      │ │
│ │ Bug fixes and security patches         │ │
│ │ [Show Changelog]                       │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ v3.11.4  - Oct 2, 2023                 │ │
│ │ [Install This Version] [Changelog]     │ │
│ └─────────────────────────────────────────┘ │
│ [Load more versions...]                    │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ User Reviews (1,342)                        │
│ ┌─────────────────────────────────────────┐ │
│ │ ⭐⭐⭐⭐⭐ Great tool!                   │ │
│ │ @john_doe · 2 weeks ago                │ │
│ │ "Works perfectly for development. No  │ │
│ │ issues so far."                        │ │
│ │ [Helpful (42)] [Report]                │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ ⭐⭐⭐⭐☆ Good, but...                  │ │
│ │ @jane_smith · 1 week ago               │ │
│ │ "Installation was smooth, but docs    │ │
│ │ could be better."                      │ │
│ │ [Helpful (8)] [Report]                 │ │
│ └─────────────────────────────────────────┘ │
│ [Write Review] [Load more...]              │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ Troubleshooting                             │
│ Q: Permission denied when installing?      │
│ A: Run: brew install --user-install-dir=~/ │
│ [See more FAQs]                            │
└─────────────────────────────────────────────┘
```

---

### 6. Settings/Preferences Screen

**Purpose:** Configure app behavior and user preferences

**Layout:**
```
┌─────────────────────────────────────────────┐
│  ⚙️ Preferences                              │
├─────────────────────────────────────────────┤
│ [General] [Updates] [Notifications]        │
│ [Accounts] [About]                         │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  General Settings                           │
│                                             │
│ ☑️ Launch at login                         │
│ ☑️ Show menu bar icon                      │
│ ☐ Dark mode                                │
│ ☑️ Check for app updates                   │
│                                             │
│ Default shell: [Zsh ▼]                    │
│ Update check interval: [Every 1h ▼]       │
│                                             │
│ Cache size: 245 MB                         │
│ [Clear Cache]                              │
│                                             │
│ Homebrew prefix: /usr/local/bin            │
│ Homebrew version: 4.1.15                   │
│                                             │
│ [Change Homebrew Location...]              │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Update Preferences                         │
│                                             │
│ ☑️ Notify about formula updates            │
│ ☑️ Notify about cask updates               │
│ ☐ Notify about tap updates                │
│ ☐ Notify about beta versions              │
│                                             │
│ Auto-update behavior:                      │
│ ○ Never (manual only)                     │
│ ● Patch versions only (1.2.x)             │
│ ○ Minor versions too (1.x.0)              │
│ ○ All versions (including major)          │
│                                             │
│ ☑️ Install updates at night (2:00 AM)      │
│ ☑️ Skip major breaking updates by default  │
│                                             │
│ [Per-Formula Settings] →                   │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Per-Formula Notification Settings          │
│                                             │
│ Search formulas...                         │
│ ┌─────────────────────────────────────────┐│
│ │ python                                  ││
│ │ Notifications: ☑️ Auto-update: ○        ││
│ │ [Edit]                                  ││
│ └─────────────────────────────────────────┘│
│ ┌─────────────────────────────────────────┐│
│ │ postgresql                              ││
│ │ Notifications: ☑️ Auto-update: ✗       ││
│ │ [Edit]                                  ││
│ └─────────────────────────────────────────┘│
│ [Add Formula...]                           │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Account Settings                           │
│                                             │
│ Signed in as: @john_doe                   │
│ [Avatar] john@example.com                  │
│                                             │
│ [Sign Out]                                 │
│                                             │
│ Connected services:                        │
│ ☑️ GitHub (for plugin submissions)        │
│ ☐ Sentry (error reporting)                │
│                                             │
│ [Manage Permissions...]                    │
└─────────────────────────────────────────────┘
```

---

## Interaction Patterns

### Installation Flow

```
User clicks "Install" (or [+] on search result)
           │
           ▼
┌──────────────────────────────────────┐
│ Install python 3.11.5?               │
│                                      │
│ This formula has dependencies:       │
│ • openssl@3                          │
│ • sqlite                             │
│ • readline                           │
│                                      │
│ Total size: ~125 MB                  │
│                                      │
│ [Cancel] [Install]                  │
└──────────────────────────────────────┘
           │
           ▼ (user confirms)
┌──────────────────────────────────────┐
│ 🔄 Installing python 3.11.5...       │
│ ████░░░░░░░░░░░░░░░░░░░░░ 25%       │
│                                      │
│ Currently: Installing openssl@3      │
│ Time: ~2 minutes remaining           │
│ [Cancel]                             │
└──────────────────────────────────────┘
           │
           ▼ (completion)
┌──────────────────────────────────────┐
│ ✅ Installation Complete!            │
│                                      │
│ python 3.11.5 installed successfully │
│ Location: /usr/local/bin/python3     │
│                                      │
│ Quick actions:                       │
│ [Run in Terminal] [Show in Finder]   │
│ [View Details] [Done]                │
└──────────────────────────────────────┘
```

### Error Handling

```
Error scenarios with recovery suggestions:

1. Formula not found
   "Formula 'pythonnn' not found"
   Suggestions:
   • Did you mean: python?
   • Search formulas...
   • View similar formulas

2. Permission denied
   "Failed to install: Permission denied"
   Suggestion:
   • BrewBar needs write access to Cellar
   • Run: sudo chown -R $(whoami) /usr/local
   • [Run Command] [Copy to Clipboard]

3. Dependency conflict
   "Cannot install: Conflicts with postgresql"
   Both need openssl 1.1 and 3.0
   Options:
   • [Uninstall postgresql] then retry
   • [View postgresql details]
   • [Show dependency graph]

4. Network error
   "Failed to download: Connection timeout"
   • Check internet connection
   • Retry: [Retry] (auto-retry in 30s...)
   • [Try different mirror]
```

---

## macOS 15 (Sequoia) UI Considerations

### Native Features to Leverage

1. **Dynamic Type & Accessibility**
   - Respect user's preferred text sizes
   - Support @Environment(\.sizeCategory)
   - Test at Extra Large & Extra Extra Large

2. **Material Design**
   - Use .thinMaterial, .ultraThinMaterial for backgrounds
   - Blur effects for depth
   - Glassmorphism for modals

3. **Cursor Effects**
   - Custom cursors for draggable items
   - Hover states (underline, highlight)
   - Context menu on right-click

4. **Animations**
   - Smooth transitions between screens
   - Loading spinners with consistent timing
   - Progress indicators (linear + circular)

5. **Haptic Feedback**
   - Light feedback on button tap
   - Success/warning/error haptics
   - Long-press menu opening

6. **Color Semantics**
   - `.red` for destructive actions (uninstall)
   - `.green` for positive (install success)
   - `.yellow` for warnings (breaking changes)
   - `.accentColor` for primary CTAs

7. **Weather Kit / Real-time Updates**
   - Live progress indicators
   - Real-time notification badges
   - Background app refresh for update checks

---

## Responsive Design

### Screen Size Breakpoints

```
iPhone     Compact  (≤375w) - Sidebar collapses
iPad       Regular  (768w)  - Split view possible
MacBook    Regular  (1024w) - Full 2-pane layout
iMac       Large    (1440w+)- Spacious, multi-column
```

### Layout Strategy

```
Compact (iPhone, Sidebar mode):
┌────────────────────┐
│ Navigation Tabs    │
│ (bottom or side)   │
├────────────────────┤
│ Main Content       │
│ (full width)       │
└────────────────────┘

Regular (iPad, Desktop):
┌──────────┬──────────────────────┐
│ Sidebar  │ Main Content         │
│ (200px)  │ (responsive)         │
│          ├──────────────────────┤
│          │ Detail Pane (opt)    │
└──────────┴──────────────────────┘
```

---

## Accessibility (a11y) Requirements

✅ **Color Contrast:** WCAG AA minimum (4.5:1 for text)

✅ **Labels:** Every UI element has accessible label
```swift
Button(action: install) {
    Label("Install", systemImage: "arrow.down")
}
.accessibilityLabel("Install python")
.accessibilityHint("Downloads and installs python to your system")
```

✅ **Focus Navigation:** Tab order makes sense
✅ **VoiceOver:** All interactive elements announced
✅ **Dynamic Type:** Scales to user's preferred size
✅ **Keyboard Navigation:** Full app usable without mouse
✅ **Reduce Motion:** Respect @Environment(\.accessibilityReduceMotion)

---

## Dark Mode Support

```swift
// Define semantic colors
Color("TextPrimary")    // Adapts to dark/light
Color("Background")     // Uses .systemBackground
Color("Accent")         // Derived from app theme

// Usage in SwiftUI
Text("Python")
    .foregroundColor(Color("TextPrimary"))
    .background(Color("Background"))
```

**Testing:**
- Verify all text readable in both modes
- Check image contrast (use SF Symbols when possible)
- Test images for appropriate display in both modes

---

## Localization Strategy

Support initial languages:
- English (en)
- Spanish (es)
- French (fr)
- German (de)
- Japanese (ja)
- Chinese Simplified (zh-Hans)

Use `.strings` files:
```swift
enum Localizable {
    static var home_title: String { 
        NSLocalizedString("home_title", comment: "Home screen title")
    }
}
```

---

## Animation Guidelines

```
Timing:
• Micro-interactions: 200ms
• Screen transitions: 300ms
• Loading spinners: 1s rotation
• Progress: Smooth easing

Easing:
.easeInOut - default
.easeOut   - dismissals
.linear    - progress bars

Avoid:
✗ Animations > 500ms (feels sluggish)
✗ Over 3 simultaneous animations
✗ Spinning on every action
```

---

## File Organization (macOS UI Layers)

```
Views/
├── Shared/
│   ├── NavigationBar.swift
│   ├── TabBar.swift
│   ├── Sidebar.swift
│   ├── StatusBar.swift
│   └── Common/
│       ├── LoadingView.swift
│       ├── ErrorView.swift
│       ├── EmptyStateView.swift
│       └── CardView.swift
│
├── Home/
│   ├── HomeView.swift
│   ├── UpdatesBannerView.swift
│   ├── FeaturedCarouselView.swift
│   ├── RecommendedGridView.swift
│   └── TrendingListView.swift
│
├── Installed/
│   ├── InstalledFormulasView.swift
│   ├── InstalledFormulaRowView.swift
│   ├── FilterChipsView.swift
│   └── SortMenuView.swift
│
├── Updates/
│   ├── UpdatesAvailableView.swift
│   ├── UpdateItemRowView.swift
│   ├── UpdateProgressView.swift
│   ├── UpdateFilterView.swift
│   └── UpdateStatusView.swift
│
├── Search/
│   ├── SearchBrowseView.swift
│   ├── SearchResultsView.swift
│   ├── AdvancedFilterView.swift
│   ├── FilterSidebarView.swift
│   └── CategoriesView.swift
│
├── Detail/
│   ├── FormulaDetailView.swift
│   ├── VersionHistoryView.swift
│   ├── DependencyGraphView.swift
│   ├── ReviewsView.swift
│   ├── DetailsHeaderView.swift
│   └── InformationSectionView.swift
│
├── Settings/
│   ├── PreferencesView.swift
│   ├── GeneralSettingsView.swift
│   ├── UpdateSettingsView.swift
│   ├── NotificationSettingsView.swift
│   ├── PerFormulaSettingsView.swift
│   ├── AccountSettingsView.swift
│   └── AboutView.swift
│
└── Modals/
    ├── InstallConfirmationView.swift
    ├── PermissionView.swift
    ├── ReleaseNotesView.swift
    ├── ChangelogView.swift
    └── ReviewFormView.swift
```

---

## Design Tokens

```swift
// Colors
let colorPrimary = Color.accentColor
let colorSuccess = Color.green
let colorWarning = Color.yellow
let colorError = Color.red
let colorText = Color.primary
let colorBackground = Color(.systemBackground)
let colorBorder = Color(.separator)

// Typography
let fontTitle1 = Font.system(.title, design: .default)
let fontTitle2 = Font.system(.title2, design: .default)
let fontBody = Font.system(.body, design: .default)
let fontCaption = Font.system(.caption, design: .default)
let fontMono = Font.system(.body, design: .monospaced)

// Spacing
let spacing_xs: CGFloat = 4
let spacing_s: CGFloat = 8
let spacing_m: CGFloat = 16
let spacing_l: CGFloat = 24
let spacing_xl: CGFloat = 32

// Corners
let cornerRadius_s: CGFloat = 4
let cornerRadius_m: CGFloat = 8
let cornerRadius_l: CGFloat = 12

// Shadows
let shadowLight = Shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
let shadowMedium = Shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
let shadowLarge = Shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
```

