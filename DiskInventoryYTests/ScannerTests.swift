import XCTest
@testable import DiskInventoryY

final class ScannerTests: XCTestCase {

    private var fixture: FixtureBuilder!

    override func setUpWithError() throws {
        fixture = try FixtureBuilder()
    }

    override func tearDownWithError() throws {
        fixture = nil
    }

    // MARK: - Helpers

    /// Drain progress events until terminal phase, then collect result.
    private func runScan(at url: URL, options: ScanOptions = .default) async throws -> ScanResult {
        let scanner = DiskScanner()
        let stream = await scanner.start(at: url, options: options)
        for await progress in stream {
            if progress.phase == .done || progress.phase == .cancelled {
                break
            }
        }
        return try await scanner.result()
    }

    // MARK: - Tests

    func testScanCountsFilesAndAggregatesSizes() async throws {
        try fixture.file("a.txt", bytes: 1_000)
        try fixture.file("b.txt", bytes: 2_500)
        try fixture.file("nested/c.txt", bytes: 4_000)
        try fixture.file("nested/deeper/d.txt", bytes: 8_000)

        let result = try await runScan(at: fixture.root)

        XCTAssertEqual(result.phase, .done)
        XCTAssertEqual(result.totalFiles, 4)
        // logicalSize is exact; physical may exceed due to FS allocation rounding.
        XCTAssertEqual(result.root.logicalSize, 15_500)
        XCTAssertGreaterThanOrEqual(result.root.physicalSize, result.root.logicalSize)
        XCTAssertEqual(result.root.itemCount, 4)

        // Tree should mirror the layout: top-level has 3 children
        // (a.txt, b.txt, nested/), regardless of order.
        XCTAssertEqual(result.root.children.count, 3)
    }

    func testScanRecordsAccessDeniedFlagAndKeepsScanning() async throws {
        try fixture.file("readable.txt", bytes: 100)
        let denied = try fixture.dir("denied")
        try fixture.file("denied/secret.txt", bytes: 999)
        try fixture.makeUnreadable(denied)
        defer { try? fixture.restorePermissions(denied) }

        let result = try await runScan(at: fixture.root)

        XCTAssertEqual(result.phase, .done)
        XCTAssertEqual(result.totalFiles, 1, "only the readable file should be counted")

        // The denied directory is still in the tree but flagged.
        let deniedNode = result.root.children.first { $0.url.lastPathComponent == "denied" }
        XCTAssertNotNil(deniedNode, "denied directory should appear in the tree")
        XCTAssertTrue(deniedNode?.flags.contains(.accessDenied) ?? false)
        XCTAssertEqual(deniedNode?.children.count ?? -1, 0)
    }

    func testScanSkipsHiddenFilesWhenDisabled() async throws {
        try fixture.file(".hidden.txt", bytes: 100)
        try fixture.file("visible.txt", bytes: 200)

        var options = ScanOptions.default
        options.includeHidden = false

        let result = try await runScan(at: fixture.root, options: options)

        XCTAssertEqual(result.totalFiles, 1)
        XCTAssertEqual(result.root.children.count, 1)
        XCTAssertEqual(result.root.children.first?.displayName, "visible.txt")
    }

    func testScanIncludesHiddenFilesByDefault() async throws {
        try fixture.file(".hidden.txt", bytes: 100)
        try fixture.file("visible.txt", bytes: 200)

        let result = try await runScan(at: fixture.root)

        XCTAssertEqual(result.totalFiles, 2)
        XCTAssertEqual(result.root.children.count, 2)
    }

    func testScanEmitsProgressEvents() async throws {
        for i in 0..<10 {
            try fixture.file("f-\(i).bin", bytes: 1_024 * (i + 1))
        }

        let scanner = DiskScanner()
        let stream = await scanner.start(at: fixture.root)

        var phases: [ScanProgress.Phase] = []
        for await progress in stream {
            phases.append(progress.phase)
            if progress.phase == .done || progress.phase == .cancelled {
                break
            }
        }
        XCTAssertTrue(phases.contains(.scanning), "scanner should report a scanning phase")
        XCTAssertEqual(phases.last, .done)
    }
}
