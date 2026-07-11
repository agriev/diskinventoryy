import XCTest
import AppKit
@testable import DiskInventoryY

/// Renders the treemap offscreen into `docs/screenshot.png` for the
/// GitHub Pages landing. Runs only on the maintainer's machine (skips
/// when the repo path doesn't exist, e.g. on CI runners) and scans the
/// repository itself — small, fast, and free of personal file names.
final class LandingScreenshotTests: XCTestCase {

    private let repoPath = "/Users/anton/workspace/DiskInventoryY"

    @MainActor
    func testGenerateLandingScreenshot() async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: repoPath),
            "maintainer-machine only"
        )

        // 1. Scan the repo folder.
        let scanner = DiskScanner()
        let stream = await scanner.start(at: URL(fileURLWithPath: repoPath))
        for await update in stream {
            if update.phase == .done || update.phase == .cancelled { break }
        }
        let result = try await scanner.result()

        // 2. Rank-assign the DIX palette exactly like RootView does.
        let colors = KindColorMap(
            rankedKindIDs: KindsAggregator.aggregate(result.root).map(\.id)
        )

        // 3. Offscreen render at 2x for a crisp landing hero.
        let size = NSSize(width: 1440, height: 900)
        let view = TreemapNSView(frame: NSRect(origin: .zero, size: size))
        view.appearance = NSAppearance(named: .darkAqua)
        view.kindColors = colors
        view.root = result.root

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return XCTFail("no bitmap rep")
        }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("png encode failed")
        }

        let out = URL(fileURLWithPath: repoPath)
            .appendingPathComponent("docs/screenshot.png")
        try png.write(to: out)

        let attrs = try FileManager.default.attributesOfItem(atPath: out.path)
        XCTAssertGreaterThan((attrs[.size] as? Int) ?? 0, 10_000,
                             "screenshot should be a real image")
    }
}
