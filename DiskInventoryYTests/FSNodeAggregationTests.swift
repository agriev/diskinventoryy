import XCTest
@testable import DiskInventoryY

final class FSNodeAggregationTests: XCTestCase {

    // MARK: - Helpers

    private func file(_ name: String, logical: Int64, physical: Int64) -> FSNode {
        FSNode(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            displayName: name,
            fileType: .regularFile,
            logicalSize: logical,
            physicalSize: physical,
            itemCount: 1
        )
    }

    private func directory(_ name: String) -> FSNode {
        FSNode(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            displayName: name,
            fileType: .directory
        )
    }

    // MARK: - Tests

    func testAppendChildBubblesSizesUp() {
        let root = directory("root")
        let a = file("a", logical: 100, physical: 128)
        let b = file("b", logical: 50,  physical: 64)

        root.appendChild(a)
        root.appendChild(b)

        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(root.logicalSize, 150)
        XCTAssertEqual(root.physicalSize, 192)
        XCTAssertEqual(root.itemCount, 2)
    }

    func testAppendDirectoryWithChildrenAggregatesAcrossLevels() {
        let root = directory("root")
        let dir = directory("subdir")
        let a = file("a", logical: 30, physical: 32)
        let b = file("b", logical: 70, physical: 96)

        dir.appendChild(a)
        dir.appendChild(b)
        root.appendChild(dir)

        XCTAssertEqual(dir.logicalSize, 100)
        XCTAssertEqual(dir.physicalSize, 128)
        // itemCount counts file leaves, not directory containers.
        XCTAssertEqual(dir.itemCount, 2)

        XCTAssertEqual(root.logicalSize, 100)
        XCTAssertEqual(root.physicalSize, 128)
        XCTAssertEqual(root.itemCount, 2)
    }

    func testRemoveChildSubtractsSizes() {
        let root = directory("root")
        let a = file("a", logical: 100, physical: 128)
        let b = file("b", logical: 200, physical: 256)
        root.appendChild(a)
        root.appendChild(b)

        XCTAssertTrue(root.removeChild(a))

        XCTAssertEqual(root.children.count, 1)
        XCTAssertIdentical(root.children.first, b)
        XCTAssertEqual(root.logicalSize, 200)
        XCTAssertEqual(root.physicalSize, 256)
        XCTAssertEqual(root.itemCount, 1)
        XCTAssertNil(a.parent)
    }

    func testReplaceChildrenAdjustsTotalsByDelta() {
        let root = directory("root")
        let oldA = file("old-a", logical: 50, physical: 64)
        let oldB = file("old-b", logical: 50, physical: 64)
        root.appendChild(oldA)
        root.appendChild(oldB)
        XCTAssertEqual(root.logicalSize, 100)

        let newA = file("new-a", logical: 200, physical: 256)
        let newB = file("new-b", logical: 100, physical: 128)
        let newC = file("new-c", logical: 50,  physical: 64)
        root.replaceChildren([newA, newB, newC])

        XCTAssertEqual(root.children.count, 3)
        XCTAssertEqual(root.logicalSize, 350)
        XCTAssertEqual(root.physicalSize, 448)
        XCTAssertEqual(root.itemCount, 3)
        for child in root.children {
            XCTAssertIdentical(child.parent, root)
            XCTAssertEqual(child.depth, 1)
        }
        XCTAssertNil(oldA.parent)
        XCTAssertNil(oldB.parent)
    }

    func testDepthIsSetAtAppendTime() {
        let root = directory("root")
        let dir = directory("dir")
        let leaf = file("leaf", logical: 1, physical: 1)

        root.appendChild(dir)
        dir.appendChild(leaf)

        XCTAssertEqual(root.depth, 0)
        XCTAssertEqual(dir.depth, 1)
        XCTAssertEqual(leaf.depth, 2)
    }

    func testAncestryReturnsRootToSelf() {
        let root = directory("root")
        let middle = directory("middle")
        let leaf = file("leaf", logical: 1, physical: 1)

        root.appendChild(middle)
        middle.appendChild(leaf)

        let chain = leaf.ancestry
        XCTAssertEqual(chain.count, 3)
        XCTAssertIdentical(chain[0], root)
        XCTAssertIdentical(chain[1], middle)
        XCTAssertIdentical(chain[2], leaf)
    }

    func testIsContainerAndIsSynthetic() {
        let dir = directory("dir")
        let regular = file("a", logical: 1, physical: 1)
        let free = FSNode(
            url: URL(fileURLWithPath: "/"),
            displayName: "Free space",
            kind: .freeSpace,
            fileType: .synthetic
        )

        XCTAssertTrue(dir.isContainer)
        XCTAssertFalse(regular.isContainer)
        XCTAssertFalse(free.isContainer)

        XCTAssertFalse(dir.isSynthetic)
        XCTAssertFalse(regular.isSynthetic)
        XCTAssertTrue(free.isSynthetic)
    }
}
