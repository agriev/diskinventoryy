import XCTest
@testable import DiskInventoryY

final class KindsAggregatorTests: XCTestCase {

    private func file(_ name: String, kindID: FileKind.ID, bytes: Int64) -> FSNode {
        FSNode(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            displayName: name,
            fileType: .regularFile,
            logicalSize: bytes,
            physicalSize: bytes,
            itemCount: 1,
            kindID: kindID
        )
    }

    private func directory(_ name: String) -> FSNode {
        FSNode(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            displayName: name,
            fileType: .directory
        )
    }

    func testAggregatesByKindID() {
        let root = directory("root")
        root.appendChild(file("a.png",  kindID: FileKind.image.id, bytes: 1_000))
        root.appendChild(file("b.png",  kindID: FileKind.image.id, bytes: 500))
        root.appendChild(file("doc.pdf", kindID: FileKind.document.id, bytes: 2_000))
        root.appendChild(file("song.mp3", kindID: FileKind.audio.id, bytes: 4_000))

        let buckets = KindsAggregator.aggregate(root)

        // Sorted descending by physical size.
        // audio=4_000, document=2_000, image=1_500 → last is image.
        XCTAssertEqual(buckets.first?.id, FileKind.audio.id)
        XCTAssertEqual(buckets.last?.id, FileKind.image.id)

        let images = buckets.first { $0.id == FileKind.image.id }
        XCTAssertEqual(images?.totalPhysical, 1_500)
        XCTAssertEqual(images?.fileCount, 2)
    }

    func testIgnoresDirectoriesAndSyntheticNodes() {
        let root = directory("root")
        let other = FSNode(
            url: URL(fileURLWithPath: "/tmp/other"),
            displayName: "Other",
            kind: .otherSpace,
            fileType: .synthetic,
            logicalSize: 9_999,
            physicalSize: 9_999,
            kindID: FileKind.other.id
        )
        root.appendChild(other)
        root.appendChild(file("real.txt", kindID: FileKind.document.id, bytes: 100))

        let buckets = KindsAggregator.aggregate(root)
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets.first?.id, FileKind.document.id)
        XCTAssertEqual(buckets.first?.totalPhysical, 100)
    }

    func testEmptyTreeProducesNoAggregates() {
        let root = directory("empty")
        XCTAssertTrue(KindsAggregator.aggregate(root).isEmpty)
    }
}
