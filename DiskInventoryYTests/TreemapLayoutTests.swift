import XCTest
@testable import DiskInventoryY

final class TreemapLayoutTests: XCTestCase {

    private func file(_ name: String, bytes: Int64) -> FSNode {
        FSNode(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            displayName: name,
            fileType: .regularFile,
            logicalSize: bytes,
            physicalSize: bytes,
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

    private func absoluteApprox(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.5) -> Bool {
        abs(a - b) <= tolerance
    }

    func testEmptyTreeProducesOnlyRootCell() {
        let root = directory("root")
        let cells = TreemapLayout.layout(root: root, bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells.first?.rect, CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    func testZeroBoundsProducesNoCells() {
        let root = directory("root")
        root.appendChild(file("a", bytes: 10))
        let cells = TreemapLayout.layout(root: root, bounds: .zero)
        XCTAssertTrue(cells.isEmpty)
    }

    func testCellsCoverContainer() {
        let root = directory("root")
        root.appendChild(file("a", bytes: 60))
        root.appendChild(file("b", bytes: 30))
        root.appendChild(file("c", bytes: 10))

        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        let cells = TreemapLayout.layout(
            root: root,
            bounds: bounds,
            options: TreemapLayout.Options(depthInset: 0, minLeafEdge: 0.5, maxDepth: 32)
        )

        let leafCells = cells.filter { $0.depth == 1 }
        XCTAssertEqual(leafCells.count, 3)

        let totalArea = leafCells.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        let expected = Double(bounds.width * bounds.height)
        XCTAssertEqual(totalArea, expected, accuracy: 1.0,
                       "leaf cells should tile the parent rectangle")
    }

    func testCellAreasAreProportionalToSizes() {
        let root = directory("root")
        // Three children with a clear 4:2:1 size ratio. After squarified
        // packing, their drawn areas should reflect the same ratio.
        let a = file("a", bytes: 4_000)
        let b = file("b", bytes: 2_000)
        let c = file("c", bytes: 1_000)
        root.appendChild(a)
        root.appendChild(b)
        root.appendChild(c)

        let cells = TreemapLayout.layout(
            root: root,
            bounds: CGRect(x: 0, y: 0, width: 700, height: 700),
            options: TreemapLayout.Options(depthInset: 0, minLeafEdge: 0.5, maxDepth: 32)
        )
        guard let cellA = cells.first(where: { $0.nodeID == ObjectIdentifier(a) }),
              let cellB = cells.first(where: { $0.nodeID == ObjectIdentifier(b) }),
              let cellC = cells.first(where: { $0.nodeID == ObjectIdentifier(c) }) else {
            return XCTFail("missing cells for one or more children")
        }
        let areaA = cellA.rect.width * cellA.rect.height
        let areaB = cellB.rect.width * cellB.rect.height
        let areaC = cellC.rect.width * cellC.rect.height

        XCTAssertEqual(Double(areaA / areaB), 2.0, accuracy: 0.05)
        XCTAssertEqual(Double(areaB / areaC), 2.0, accuracy: 0.05)
    }

    func testZeroSizeChildrenAreSkipped() {
        let root = directory("root")
        let a = file("a", bytes: 100)
        let zero = file("zero", bytes: 0)
        root.appendChild(a)
        root.appendChild(zero)

        let cells = TreemapLayout.layout(
            root: root,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 100),
            options: TreemapLayout.Options(depthInset: 0, minLeafEdge: 0.5, maxDepth: 32)
        )

        XCTAssertNil(cells.first(where: { $0.nodeID == ObjectIdentifier(zero) }),
                     "zero-size children should be skipped")
        XCTAssertNotNil(cells.first(where: { $0.nodeID == ObjectIdentifier(a) }))
    }

    func testNestedTreeProducesCellsAtDeeperDepths() {
        let root = directory("root")
        let dir = directory("dir")
        let inner = file("inner", bytes: 100)
        dir.appendChild(inner)
        root.appendChild(dir)

        let cells = TreemapLayout.layout(
            root: root,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 200),
            options: TreemapLayout.Options(depthInset: 0, minLeafEdge: 0.5, maxDepth: 32)
        )

        XCTAssertTrue(cells.contains(where: { $0.depth == 0 && $0.nodeID == ObjectIdentifier(root) }))
        XCTAssertTrue(cells.contains(where: { $0.depth == 1 && $0.nodeID == ObjectIdentifier(dir) }))
        XCTAssertTrue(cells.contains(where: { $0.depth == 2 && $0.nodeID == ObjectIdentifier(inner) }))
    }

    // MARK: - Slice & Dice

    func testSliceAndDiceCoversContainer() {
        let root = directory("root")
        root.appendChild(file("a", bytes: 60))
        root.appendChild(file("b", bytes: 30))
        root.appendChild(file("c", bytes: 10))

        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        var options = TreemapLayout.Options(depthInset: 0, minLeafEdge: 0.5, maxDepth: 32)
        options.algorithm = .sliceAndDice

        let cells = TreemapLayout.layout(root: root, bounds: bounds, options: options)
        let leafCells = cells.filter { $0.depth == 1 }
        XCTAssertEqual(leafCells.count, 3)

        // Strips align on the longer axis: container is square, so
        // direction is horizontal (width >= height in our impl).
        let totalArea = leafCells.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        XCTAssertEqual(totalArea, Double(bounds.width * bounds.height), accuracy: 1.0)
    }

    func testSliceAndDiceProducesRectanglesOfFullContainerHeight() {
        let root = directory("root")
        root.appendChild(file("a", bytes: 40))
        root.appendChild(file("b", bytes: 60))

        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 200)
        var options = TreemapLayout.Options(depthInset: 0, minLeafEdge: 0.5, maxDepth: 32)
        options.algorithm = .sliceAndDice

        let cells = TreemapLayout.layout(root: root, bounds: bounds, options: options)
        let leafCells = cells.filter { $0.depth == 1 }
        // For a wide container, slice-and-dice with horizontal axis
        // gives strips that span full height.
        for cell in leafCells {
            XCTAssertEqual(cell.rect.height, bounds.height, accuracy: 0.5)
        }
    }

    func testSliceAndDiceFlipsAxisOnRecursion() {
        let root = directory("root")
        let dir = directory("dir")
        dir.appendChild(file("inner-a", bytes: 50))
        dir.appendChild(file("inner-b", bytes: 50))
        root.appendChild(dir)

        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        var options = TreemapLayout.Options(depthInset: 0, minLeafEdge: 0.5, maxDepth: 32)
        options.algorithm = .sliceAndDice

        let cells = TreemapLayout.layout(root: root, bounds: bounds, options: options)
        let inner = cells.filter { $0.depth == 2 }
        XCTAssertEqual(inner.count, 2)
        // Top level was horizontal; inner level should be vertical
        // (axis flipped). Check that two children share the SAME x and
        // differ in y (not the other way around).
        if let first = inner.first, let second = inner.dropFirst().first {
            XCTAssertEqual(first.rect.minX, second.rect.minX, accuracy: 0.5)
            XCTAssertNotEqual(first.rect.minY, second.rect.minY, accuracy: 0.5)
        }
    }

    func testLayoutIsDeterministicForFixedInput() {
        let root1 = directory("root")
        for i in 1...10 {
            root1.appendChild(file("f\(i)", bytes: Int64(100 * i)))
        }
        let root2 = directory("root")
        for i in 1...10 {
            root2.appendChild(file("f\(i)", bytes: Int64(100 * i)))
        }

        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let a = TreemapLayout.layout(root: root1, bounds: bounds)
        let b = TreemapLayout.layout(root: root2, bounds: bounds)
        XCTAssertEqual(a.count, b.count)
        for (lhs, rhs) in zip(a, b) {
            XCTAssertTrue(absoluteApprox(lhs.rect.minX, rhs.rect.minX))
            XCTAssertTrue(absoluteApprox(lhs.rect.minY, rhs.rect.minY))
            XCTAssertTrue(absoluteApprox(lhs.rect.width, rhs.rect.width))
            XCTAssertTrue(absoluteApprox(lhs.rect.height, rhs.rect.height))
        }
    }
}
