# DiskInventoryY

A modern disk inventory tool for macOS, written in Swift and SwiftUI. Treemap-based visualization of disk usage, ground-up rewrite of [Disk Inventory X](https://gitlab.com/tderlien/disk-inventory-x).

> Status: **v0.4.0** — proper AppIcon (squircle with a stylized squarified-treemap top, Y-shape negative space, light SSD silhouette). Plus everything from v0.3.0 (multi-window, NSOutlineView host, cushion-shaded treemap, drag-out file URLs, drill-in/breadcrumbs, live volumes sidebar, recents, Kinds bar). Outstanding: `getattrlistbulk(2)` fast path, signed/notarized release builds.

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel (universal binary)
- Full Disk Access is required to scan TCC-protected paths (Mail, Messages, the system Library, etc.). DiskInventoryY shows a banner with a one-click deeplink when needed.

## Features (planned for v0.1)

- Scan any folder or volume; cancellation; subtree refresh.
- Squarified treemap with cushion shading; SwiftUI + AppKit hybrid for performance.
- Outline view of the file tree with sortable columns (NSOutlineView under the hood).
- Inspector panel with Quick Look thumbnail, sizes (logical + physical), kind, owner, dates.
- Color-by-kind (deterministic palette) and a horizontal Kinds bar with one-tap filtering.
- Drag and drop file URLs out of the app; drop folders in to start a scan.
- Save and reopen scans (`.dscan` JSON+gzip).
- Reveal in Finder, Quick Look, Move to Trash with Undo.

## Building

```sh
xcodegen generate
open DiskInventoryY.xcodeproj
```

Then `Cmd+R` in Xcode. Tests via `Cmd+U`. No SPM or CocoaPods dependencies — just the system frameworks.

CLI build:

```sh
xcodebuild -project DiskInventoryY.xcodeproj \
  -scheme DiskInventoryY \
  -destination 'platform=macOS' \
  build test
```

Release build (DMG):

```sh
Scripts/BuildRelease.sh
```

## Project structure

```
DiskInventoryY/
├── DiskInventoryY/          # app sources (App, Models, Services, ViewModels, Views, Utilities, Resources)
├── DiskInventoryYTests/     # XCTest unit tests
├── DiskInventoryYUITests/   # XCUITest smoke tests
├── Configs/                 # *.xcconfig
├── Scripts/                 # BuildRelease.sh, notarize.sh, ExportOptions.plist
├── .github/workflows/       # CI + release pipelines
└── project.yml              # xcodegen spec
```

## Origin and credit

DiskInventoryY is a from-scratch Swift/SwiftUI rewrite of [Disk Inventory X](https://gitlab.com/tderlien/disk-inventory-x) by Tjark Derlien, originally released in 2003 under GPL. The squarified treemap layout follows the algorithm popularized by [KDirStat](https://kdirstat.sourceforge.net/) (Stefan Hundhammer). See [`NOTICE`](NOTICE) for full acknowledgements.

## Differences from Disk Inventory X

- Pure Swift / SwiftUI; macOS 14+.
- Apple Silicon native (universal binary; arm64 + x86_64).
- Zero third-party dependencies (Omni and CocoaTech frameworks are gone).
- `getattrlistbulk(2)` for fast scans on APFS.
- Hardlink-aware (the original double-counted hardlinks).
- APFS purgeable storage accounted for in the *Other space* bucket.
- English-only localization (one Swift String Catalog).
- Modern macOS 14 layout: `NavigationSplitView`, `.inspector`, SF Symbols, Asset Catalog.
- Dark Mode aware palette.

## Releases & signing

Tagged releases (`v*`) trigger `.github/workflows/release.yml`. Notarized builds require these GitHub secrets:

- `APPLE_ID` — Apple ID email used for notarization.
- `TEAM_ID` — Developer Team ID.
- `APPLE_APP_PASSWORD` — app-specific password.
- `MACOS_CERTIFICATE` (base64 .p12) and `MACOS_CERTIFICATE_PWD` — Developer ID Application cert.

Without these, the workflow ships an unsigned `.app` zipped into the release artifact (Gatekeeper override required at first launch).

## License

[GPL-3.0-or-later](LICENSE). DiskInventoryY is a derivative work of Disk Inventory X (GPL-3.0) and remains under GPL-3.0.
