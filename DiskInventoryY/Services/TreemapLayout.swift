import CoreGraphics
import Foundation

/// One rectangle in a treemap layout.
struct TreemapCell: Sendable, Hashable {
    /// Identity of the FSNode this cell represents. Stored as the
    /// `ObjectIdentifier`'s underlying pointer so the algorithm stays
    /// pure (no FSNode references to manage memory of in tests).
    var nodeID: ObjectIdentifier
    var rect: CGRect
    var depth: UInt8
    var size: Int64
}

/// Squarified treemap layout (Bruls/Huijsen/van Wijk, 2000).
///
/// `layout(root:)` returns a flat list of cells suitable for a single
/// CG draw pass. The algorithm is pure and exposed for unit testing
/// independently of any view.
enum TreemapLayout {

    struct Options: Sendable {
        /// Pixels of inset per depth — creates the visible border that
        /// separates parent and child levels. Set to 0 to disable.
        var depthInset: CGFloat = 1
        /// Cells smaller than this in either dimension are coalesced
        /// into the parent (LOD).
        var minLeafEdge: CGFloat = 1
        /// Hard depth cutoff to stop layout in pathological trees.
        var maxDepth: UInt8 = 32

        static let `default` = Options()
    }

    /// Public entry. The root node's full `bounds` is filled, then each
    /// child's allotted rectangle is recursed into.
    static func layout(
        root: FSNode,
        bounds: CGRect,
        options: Options = .default
    ) -> [TreemapCell] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        var cells: [TreemapCell] = []
        cells.reserveCapacity(2_048)
        layoutNode(root, in: bounds, depth: 0, options: options, into: &cells)
        return cells
    }

    // MARK: - Recursion

    private static func layoutNode(
        _ node: FSNode,
        in rect: CGRect,
        depth: UInt8,
        options: Options,
        into cells: inout [TreemapCell]
    ) {
        guard rect.width >= options.minLeafEdge, rect.height >= options.minLeafEdge else { return }

        // Emit the cell for this node before recursing — we want the
        // parent rectangle visible behind the children.
        cells.append(TreemapCell(
            nodeID: ObjectIdentifier(node),
            rect: rect,
            depth: depth,
            size: max(node.physicalSize, 0)
        ))

        guard depth < options.maxDepth, !node.children.isEmpty else { return }

        let inset = options.depthInset
        let inner = rect.insetBy(dx: inset, dy: inset)
        guard inner.width > 0, inner.height > 0 else { return }

        let positiveChildren = node.children
            .filter { $0.physicalSize > 0 }
            .sorted { $0.physicalSize > $1.physicalSize }
        guard !positiveChildren.isEmpty else { return }

        let total = positiveChildren.reduce(Int64(0)) { $0 &+ $1.physicalSize }
        guard total > 0 else { return }

        squarify(
            children: positiveChildren,
            totalSize: total,
            container: inner,
            depth: depth &+ 1,
            options: options,
            into: &cells
        )
    }

    // MARK: - Squarified packing

    private static func squarify(
        children: [FSNode],
        totalSize: Int64,
        container initialContainer: CGRect,
        depth: UInt8,
        options: Options,
        into cells: inout [TreemapCell]
    ) {
        var container = initialContainer
        var remainingSize = totalSize
        var index = 0

        while index < children.count {
            let shorterSide = min(container.width, container.height)
            guard shorterSide > 0 else { return }

            // Build up a row by greedily appending children while the
            // worst aspect ratio improves (or stays equal).
            var row: [FSNode] = [children[index]]
            var rowSize = children[index].physicalSize
            var bestWorst = worst(row: [children[index].physicalSize],
                                  rowSize: rowSize,
                                  totalSize: remainingSize,
                                  shorterSide: shorterSide)

            var lookahead = index + 1
            while lookahead < children.count {
                let candidate = children[lookahead]
                let trialSize = rowSize &+ candidate.physicalSize
                let trialSizes = row.map(\.physicalSize) + [candidate.physicalSize]
                let trialWorst = worst(row: trialSizes,
                                       rowSize: trialSize,
                                       totalSize: remainingSize,
                                       shorterSide: shorterSide)
                if trialWorst <= bestWorst {
                    row.append(candidate)
                    rowSize = trialSize
                    bestWorst = trialWorst
                    lookahead += 1
                } else {
                    break
                }
            }

            let consumed = lookahead - index
            placeRow(
                row: row,
                rowSize: rowSize,
                totalSize: remainingSize,
                container: &container,
                depth: depth,
                options: options,
                into: &cells
            )

            // Recurse into each child placed in this row.
            // We refer back via `row[i].physicalSize` to compute the rect
            // — placeRow has already set it via the `rect` we appended.
            for child in row where !child.children.isEmpty {
                if let cell = cells.last(where: { $0.nodeID == ObjectIdentifier(child) }) {
                    layoutNode(child, in: cell.rect, depth: depth, options: options, into: &cells)
                }
            }

            remainingSize &-= rowSize
            index += consumed
        }
    }

    private static func placeRow(
        row: [FSNode],
        rowSize: Int64,
        totalSize: Int64,
        container: inout CGRect,
        depth: UInt8,
        options: Options,
        into cells: inout [TreemapCell]
    ) {
        guard !row.isEmpty, totalSize > 0 else { return }

        let shorterSide = min(container.width, container.height)
        let rowFraction = CGFloat(Double(rowSize) / Double(totalSize))
        let longerSpan = max(container.width, container.height) * rowFraction

        let layoutHorizontally = container.width >= container.height

        var offset: CGFloat = 0
        for child in row {
            let childFraction = CGFloat(Double(child.physicalSize) / Double(rowSize))
            let span = shorterSide * childFraction

            let cellRect: CGRect
            if layoutHorizontally {
                cellRect = CGRect(
                    x: container.minX,
                    y: container.minY + offset,
                    width: longerSpan,
                    height: span
                )
                offset += span
            } else {
                cellRect = CGRect(
                    x: container.minX + offset,
                    y: container.minY,
                    width: span,
                    height: longerSpan
                )
                offset += span
            }

            cells.append(TreemapCell(
                nodeID: ObjectIdentifier(child),
                rect: cellRect,
                depth: depth,
                size: child.physicalSize
            ))
        }

        // Shrink the container to what's left for the remaining rows.
        if layoutHorizontally {
            container = CGRect(
                x: container.minX + longerSpan,
                y: container.minY,
                width: max(container.width - longerSpan, 0),
                height: container.height
            )
        } else {
            container = CGRect(
                x: container.minX,
                y: container.minY + longerSpan,
                width: container.width,
                height: max(container.height - longerSpan, 0)
            )
        }
    }

    /// Worst-case (highest) aspect ratio in the row if it were drawn
    /// against `shorterSide` of the remaining container.
    private static func worst(
        row sizes: [Int64],
        rowSize: Int64,
        totalSize: Int64,
        shorterSide: CGFloat
    ) -> Double {
        guard let smallest = sizes.min(), let largest = sizes.max(), totalSize > 0 else {
            return .infinity
        }
        let scale = Double(rowSize) / Double(totalSize)
        let area = Double(shorterSide) * Double(shorterSide) * scale
        guard area > 0 else { return .infinity }
        let big = Double(largest)
        let small = Double(smallest)
        let rowSum = Double(rowSize)
        let r1 = (big * Double(shorterSide) * Double(shorterSide)) / (rowSum * rowSum)
        let r2 = (rowSum * rowSum) / (small * Double(shorterSide) * Double(shorterSide))
        return max(r1, r2)
    }
}
