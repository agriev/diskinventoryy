import XCTest
@testable import DiskInventoryY

final class KindColorMapTests: XCTestCase {

    private func rgb(_ color: NSColor) -> (CGFloat, CGFloat, CGFloat) {
        let c = color.usingColorSpace(.sRGB)!
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }

    func testDixPaletteValuesMatchOriginal() {
        // Verbatim values from Disk Inventory X FileTypeColors.m.
        let expected: [(CGFloat, CGFloat, CGFloat)] = [
            (0, 0, 1), (1, 0, 0), (0, 1, 0), (0, 1, 1), (1, 0, 1), (1, 1, 0),
            (0.58, 0.58, 1), (1, 0.58, 0.58), (0.58, 1, 0.58),
            (0.58, 1, 1), (1, 0.58, 1), (1, 1, 0.58),
        ]
        XCTAssertEqual(KindColorMap.dixPalette.count, expected.count)
        for (got, want) in zip(KindColorMap.dixPalette, expected) {
            XCTAssertEqual(got.r, want.0, accuracy: 0.001)
            XCTAssertEqual(got.g, want.1, accuracy: 0.001)
            XCTAssertEqual(got.b, want.2, accuracy: 0.001)
        }
    }

    func testLargestKindGetsBlueSecondGetsRed() {
        let map = KindColorMap(rankedKindIDs: [
            FileKind.video.id,     // rank 1 — biggest
            FileKind.image.id,     // rank 2
            FileKind.code.id,      // rank 3
        ])
        let first = rgb(map.nsColor(for: FileKind.video.id))
        XCTAssertEqual(first.0, 0, accuracy: 0.001)
        XCTAssertEqual(first.1, 0, accuracy: 0.001)
        XCTAssertEqual(first.2, 1, accuracy: 0.001)

        let second = rgb(map.nsColor(for: FileKind.image.id))
        XCTAssertEqual(second.0, 1, accuracy: 0.001)
        XCTAssertEqual(second.1, 0, accuracy: 0.001)
        XCTAssertEqual(second.2, 0, accuracy: 0.001)

        let third = rgb(map.nsColor(for: FileKind.code.id))
        XCTAssertEqual(third.0, 0, accuracy: 0.001)
        XCTAssertEqual(third.1, 1, accuracy: 0.001)
        XCTAssertEqual(third.2, 0, accuracy: 0.001)
    }

    func testOverflowKindsGetGrayscaleRamp() {
        // 14 ranked kinds: 12 palette slots + 2 grayscale.
        let ids = (0..<14).map { "kind-\($0)" }
        let map = KindColorMap(rankedKindIDs: ids)

        let thirteenth = rgb(map.nsColor(for: "kind-12"))
        XCTAssertEqual(thirteenth.0, 0.60, accuracy: 0.001)  // 0.05 * 12
        XCTAssertEqual(thirteenth.0, thirteenth.1, accuracy: 0.001)
        XCTAssertEqual(thirteenth.1, thirteenth.2, accuracy: 0.001)

        let fourteenth = rgb(map.nsColor(for: "kind-13"))
        XCTAssertEqual(fourteenth.0, 0.65, accuracy: 0.001)  // 0.05 * 13
    }

    func testSyntheticKindsPinnedToGreysAndSkipPaletteSlots() {
        let map = KindColorMap(rankedKindIDs: [
            FileKind.otherSpace.id,   // synthetic — must not consume blue
            FileKind.image.id,
        ])
        let other = rgb(map.nsColor(for: FileKind.otherSpace.id))
        XCTAssertEqual(other.0, 0.55, accuracy: 0.001)
        XCTAssertEqual(other.0, other.1, accuracy: 0.001)

        // image is the first *real* kind → blue, not red.
        let image = rgb(map.nsColor(for: FileKind.image.id))
        XCTAssertEqual(image.2, 1, accuracy: 0.001)
        XCTAssertEqual(image.0, 0, accuracy: 0.001)
    }

    func testUnknownKindAtLookupIsDeterministic() {
        let map = KindColorMap(rankedKindIDs: [FileKind.image.id])
        let a = map.nsColor(for: "never-ranked")
        let b = map.nsColor(for: "never-ranked")
        XCTAssertEqual(a, b)
    }

    func testFallbackMapIsStable() {
        XCTAssertEqual(KindColorMap.fallback, KindColorMap.fallback)
        // Priority order: image is first in allKnown → blue.
        let image = rgb(KindColorMap.fallback.nsColor(for: FileKind.image.id))
        XCTAssertEqual(image.2, 1, accuracy: 0.001)
    }
}
