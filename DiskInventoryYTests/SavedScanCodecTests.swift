import XCTest
@testable import DiskInventoryY

final class SavedScanCodecTests: XCTestCase {

    private func file(_ name: String, bytes: Int64) -> FSNode {
        FSNode(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            displayName: name,
            fileType: .regularFile,
            logicalSize: bytes,
            physicalSize: bytes,
            itemCount: 1,
            kindID: FileKind.document.id,
            mtime: Date(timeIntervalSince1970: 1_700_000_000),
            flags: []
        )
    }

    private func directory(_ name: String) -> FSNode {
        FSNode(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            displayName: name,
            fileType: .directory,
            kindID: FileKind.other.id
        )
    }

    private func sampleTree() -> FSNode {
        let root = directory("root")
        let dir = directory("subdir")
        dir.appendChild(file("a.txt", bytes: 100))
        dir.appendChild(file("b.txt", bytes: 200))
        root.appendChild(file("c.dat", bytes: 50))
        root.appendChild(dir)
        return root
    }

    func testEncodeDecodeRoundtripPreservesStructureAndSizes() throws {
        let root = sampleTree()
        let saved = SavedScan(
            schema: SavedScan.currentSchema,
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
            rootURL: root.url,
            volume: nil,
            tree: SavedScanCodec.snapshot(root)
        )

        let encoded = try SavedScanCodec.encode(saved)
        XCTAssertGreaterThan(encoded.count, 0)

        let decoded = try SavedScanCodec.decode(encoded)
        XCTAssertEqual(decoded.schema, SavedScan.currentSchema)
        XCTAssertEqual(decoded.scannedAt, saved.scannedAt)
        XCTAssertEqual(decoded.rootURL, saved.rootURL)

        let restored = SavedScanCodec.materialize(decoded.tree)
        XCTAssertEqual(restored.displayName, root.displayName)
        XCTAssertEqual(restored.children.count, root.children.count)
        XCTAssertEqual(restored.logicalSize, root.logicalSize)
        XCTAssertEqual(restored.physicalSize, root.physicalSize)
        XCTAssertEqual(restored.itemCount, root.itemCount)

        let restoredDir = restored.children.first { $0.displayName == "subdir" }
        XCTAssertEqual(restoredDir?.children.count, 2)
        XCTAssertEqual(restoredDir?.logicalSize, 300)
    }

    func testCompressedDataIsSmallerThanRawJSON() throws {
        // Wide-and-shallow tree compresses well: 200 leaves of similar shape.
        let root = directory("wide")
        for i in 0..<200 {
            root.appendChild(file("file\(i).txt", bytes: Int64(i * 10)))
        }
        let saved = SavedScan(
            scannedAt: Date(timeIntervalSince1970: 0),
            rootURL: root.url,
            volume: nil,
            tree: SavedScanCodec.snapshot(root)
        )
        let raw = try JSONEncoder().encode(saved)
        let compressed = try SavedScanCodec.encode(saved)
        XCTAssertLessThan(compressed.count, raw.count, "zlib should shrink JSON")
    }

    func testDecodeAcceptsUncompressedJSON() throws {
        let root = file("x.txt", bytes: 42)
        let saved = SavedScan(
            scannedAt: Date(timeIntervalSince1970: 0),
            rootURL: root.url,
            volume: nil,
            tree: SavedScanCodec.snapshot(root)
        )
        let raw = try {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(saved)
        }()
        let decoded = try SavedScanCodec.decode(raw)
        XCTAssertEqual(decoded.tree.logicalSize, 42)
    }

    func testDecodeRejectsFutureSchema() throws {
        let root = file("x.txt", bytes: 1)
        let future = SavedScan(
            schema: SavedScan.currentSchema + 99,
            scannedAt: Date(),
            rootURL: root.url,
            volume: nil,
            tree: SavedScanCodec.snapshot(root)
        )
        let encoded = try SavedScanCodec.encode(future)
        XCTAssertThrowsError(try SavedScanCodec.decode(encoded)) { error in
            guard case SavedScanCodec.CodecError.schemaMismatch = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}
