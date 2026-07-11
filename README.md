# DiskInventoryY

A modern disk inventory tool for macOS, written in Swift and SwiftUI. Treemap-based visualization of disk usage, ground-up rewrite of [Disk Inventory X](https://gitlab.com/tderlien/disk-inventory-x).

> Status: **v1.2.0** — the authentic Disk Inventory X color scheme. The treemap palette is ported verbatim from DIX's `FileTypeColors.m` (blue, red, green, cyan, magenta, yellow + light variants, grayscale ramp past 12 kinds) and assigned by size rank per scan — the dominant kind is always blue, the runner-up red. Also fixes a race where rapid re-scans could stomp a fresh scan's state with "Scan ended unexpectedly". Plus everything from v1.1.0 (parallel scanner, DIX-style file-only coloring, single-window navigation).
>
> Landing page: <https://agriev.github.io/diskinventoryy/>. Builds are universal (arm64 + x86_64); releases from v1.2.1 onward are Developer ID-signed and notarized (built locally via `Scripts/BuildSignedRelease.sh` — no Apple credentials ever leave the maintainer's Keychain).

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

Tagged releases (`v*`) trigger `.github/workflows/release.yml`, which produces an **ad-hoc-signed** DMG as a CI artifact; the published DMG is then replaced by a locally built, Developer ID-signed and notarized one (`Scripts/BuildSignedRelease.sh` + `gh release upload --clobber`). Releases ≤ v1.2.0 still carry the ad-hoc build — right-click → Open on first launch for those.

For a properly signed and notarized build there are two paths.

### Path A: locally, no secrets in GitHub *(recommended)*

Everything stays on your Mac — no Apple credentials in the repo, in env vars, or in GitHub Actions secrets.

**One-time setup:**

1. Be enrolled in the Apple Developer Program (≈ $99/year).
2. Create a *Developer ID Application* certificate at <https://developer.apple.com/account/resources/certificates/> and import it into the login Keychain. Verify with `security find-identity -p codesigning -v`.
3. Generate an app-specific password at <https://account.apple.com> → Sign-In and Security → App-Specific Passwords.
4. Stash it in the system Keychain (one prompt; nothing on disk in plaintext):

   ```sh
   Scripts/StoreNotaryCreds.sh
   ```

   The script wraps `xcrun notarytool store-credentials` and saves a profile named `DiskInventoryY-Notarization`.

**Each release:**

```sh
git tag v1.1.0 && git push --tags        # CI builds the unsigned DMG
Scripts/BuildSignedRelease.sh            # local: sign + notarize + DMG
gh release upload v1.1.0 build/DiskInventoryY-1.1.0.dmg \
  --repo agriev/diskinventoryy --clobber
```

`BuildSignedRelease.sh` auto-detects your Developer ID identity from Keychain, sets `--options=runtime`, submits to Apple's notary service via the stored profile, staples the ticket onto both the `.app` and the DMG, and packages them with a `/Applications` shortcut. It honours `SKIP_NOTARIZE=1` and `SKIP_DMG=1` if you want to break the steps apart.

### Path B: GitHub Actions notarizes for you

If you'd rather have CI do it on every tag, add these repo secrets at *Settings → Secrets and variables → Actions*:

| Secret | What it is |
|---|---|
| `APPLE_ID` | Apple ID email enrolled in the Developer Program |
| `TEAM_ID` | 10-character team identifier (`developer.apple.com/account` → Membership) |
| `APPLE_APP_PASSWORD` | app-specific password from `account.apple.com` |

Optional, for full codesigning in CI (not yet wired):

| Secret | What it is |
|---|---|
| `MACOS_CERTIFICATE` | base64-encoded `.p12` of the Developer ID Application cert |
| `MACOS_CERTIFICATE_PWD` | the `.p12` password |

The workflow already calls `notarize.sh` when those vars are present.

## License

[GPL-3.0-or-later](LICENSE). DiskInventoryY is a derivative work of Disk Inventory X (GPL-3.0) and remains under GPL-3.0.
