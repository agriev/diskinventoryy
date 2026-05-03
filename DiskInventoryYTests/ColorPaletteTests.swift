import XCTest
@testable import DiskInventoryY

final class ColorPaletteTests: XCTestCase {

    func testCuratedKindsHaveStableColorAcrossInstances() {
        let a = ColorPalette()
        let b = ColorPalette()
        for kind in FileKind.allKnown {
            XCTAssertEqual(
                a.nsColor(for: kind.id),
                b.nsColor(for: kind.id),
                "color for \(kind.id) drifted between palette instances"
            )
        }
    }

    func testFnv1aIsDeterministic() {
        XCTAssertEqual(ColorPalette.fnv1aHash("image"), ColorPalette.fnv1aHash("image"))
        XCTAssertEqual(ColorPalette.fnv1aHash("video"), ColorPalette.fnv1aHash("video"))
        XCTAssertNotEqual(ColorPalette.fnv1aHash("image"), ColorPalette.fnv1aHash("video"))
    }

    func testUnknownIdProducesDeterministicColor() {
        let palette = ColorPalette()
        let first = palette.nsColor(for: "unknown-bucket-xyz")
        let second = palette.nsColor(for: "unknown-bucket-xyz")
        XCTAssertEqual(first, second)
    }

    func testFnv1aGoldenValues() {
        // Pinning a couple of FNV-1a outputs makes accidental changes to
        // the algorithm caught immediately.
        XCTAssertEqual(ColorPalette.fnv1aHash(""),     0x811c_9dc5)
        XCTAssertEqual(ColorPalette.fnv1aHash("a"),    0xe40c_292c)
        XCTAssertEqual(ColorPalette.fnv1aHash("foobar"), 0xbf9c_f968)
    }
}
