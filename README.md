# DiskInventoryY

A modern disk inventory tool for macOS, written in Swift and SwiftUI. Treemap-based visualization of disk usage, ground-up rewrite of [Disk Inventory X](https://gitlab.com/tderlien/disk-inventory-x).

> Status: **v1.0.0** — feature-complete: bulk `getattrlistbulk(2)` enumerator with hardlink dedupe, synthetic Free/Other-space siblings on volume scans, Save/Open .dscan via File menu (⌘S, ⇧⌘O), shared right-click context menu (treemap + outline), Refresh Selection (⇧⌘R), drill-in fade animation gated on Reduce Motion, two layout algorithms (Squarified / Slice & Dice), wired Settings, multi-window. 46 unit tests on CI.
>
> Landing page: <https://agriev.github.io/diskinventoryy/>. Builds are universal (arm64 + x86_64) but ad-hoc-signed; see [Releases & signing](#releases--signing) below for the secrets needed to ship notarized DMGs.

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

Tagged releases (`v*`) trigger `.github/workflows/release.yml`. Without secrets the workflow falls back to an ad-hoc-signed `.app` packaged into a DMG; users have to right-click → Open the first time, or run `xattr -dr com.apple.quarantine /Applications/DiskInventoryY.app`.

To ship notarized DMGs add these repo secrets (Settings → Secrets and variables → Actions):

| Secret | What it is | How to get it |
|---|---|---|
| `APPLE_ID` | Apple ID email | the Apple ID enrolled in the Apple Developer Program |
| `TEAM_ID` | 10-character team identifier | <https://developer.apple.com/account#MembershipDetailsCard> |
| `APPLE_APP_PASSWORD` | app-specific password for `notarytool` | <https://account.apple.com> → Sign-In and Security → App-Specific Passwords |
| `MACOS_CERTIFICATE` *(future)* | base64-encoded `.p12` of the Developer ID Application cert | export the cert from Keychain → `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PWD` *(future)* | password for the `.p12` | whatever you set on export |

After the first three are set, the next `git tag v0.6.1 && git push --tags` will: archive the app, run `notarytool submit --wait`, staple the ticket, and attach the notarized DMG to the GitHub Release. The fourth and fifth secrets aren't read by the current workflow yet — they're slotted in for when we wire actual codesigning into `Scripts/BuildRelease.sh` (currently relying on whatever signing identity is available locally).

## License

[GPL-3.0-or-later](LICENSE). DiskInventoryY is a derivative work of Disk Inventory X (GPL-3.0) and remains under GPL-3.0.
