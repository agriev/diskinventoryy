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

/// Treemap layout algorithms. Two are supported:
///
/// - `squarified` — Bruls/Huijsen/van Wijk 2000. Same family used by
///   modern KDirStat / QDirStat / Disk Inventory X (via the OmniGroup
///   framework). Cells are packed into rows that minimize the worst
///   aspect ratio.
/// - `sliceAndDice` — the classical "slice and dice" treemap from
///   Shneiderman 1992, the look the early KDirStat 1.x and many
///   academic visualizations used. Children fill alternating
///   horizontal / vertical strips ordered by size.
///
/// `layout(root:)` returns a flat list of cells suitable for a single
/// CG draw pass. The algorithm is pure and exposed for unit testing
/// independently of any view.
enum TreemapLayout {

    enum Algorithm: String, Sendable, CaseIterable {
        case squarified
        case sliceAndDice
    }

    enum SizeMetric: Sendable {
        case physical
        case logical

        func value(of node: FSNode) -> Int64 {
            switch self {
            case .physical: return node.physicalSize
            case .logical:  return node.logicalSize
            }
        }
    }

    struct Options: Sendable {
        var algorithm: Algorithm = .squarified
        /// Pixels of inset per depth — creates the visible border that
        /// separates parent and child levels. Set to 0 to disable.
        var depthInset: CGFloat = 1
        /// Cells smaller than this in either dimension are coalesced
        /// into the parent (LOD).
        var minLeafEdge: CGFloat = 1
        /// Hard depth cutoff to stop layout in pathological trees.
        var maxDepth: UInt8 = 32
        /// Whether to size cells by physical (allocated) size or
        /// logical size. Mirrors the `sizeMode` user preference.
        var sizeMetric: SizeMetric = .physical

        static let `default` = Options()

        /// Frames matter near the top of the hierarchy (folder
        /// grouping), but at depth the padding starves deep files of
        /// their area — DIX renders leaves edge-to-edge. Taper: full
        /// inset for the first two levels, half at three, then none.
        func inset(forDepth depth: UInt8) -> CGFloat {
            switch depth {
            case 0...1: return depthInset
            case 2:     return depthInset / 2
            default:    return 0
            }
        }
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

        let sizeOf = options.sizeMetric.value
        // Emit the cell for this node before recursing — we want the
        // parent rectangle visible behind the children.
        cells.append(TreemapCell(
            nodeID: ObjectIdentifier(node),
            rect: rect,
            depth: depth,
            size: max(sizeOf(node), 0)
        ))

        recurseChildren(of: node, in: rect, depth: depth, options: options, into: &cells)
    }

    /// Lay out `node`'s children inside `rect` WITHOUT re-emitting the
    /// node's own cell (the caller already has). Split out so squarify
    /// can recurse into already-placed rects without duplicating cells.
    private static func recurseChildren(
        of node: FSNode,
        in rect: CGRect,
        depth: UInt8,
        options: Options,
        into cells: inout [TreemapCell]
    ) {
        guard rect.width >= options.minLeafEdge, rect.height >= options.minLeafEdge else { return }
        guard depth < options.maxDepth, !node.children.isEmpty else { return }

        let sizeOf = options.sizeMetric.value
        let inset = options.inset(forDepth: depth)
        let inner = inset > 0 ? rect.insetBy(dx: inset, dy: inset) : rect
        guard inner.width > 0, inner.height > 0 else { return }

        let positiveChildren = node.children
            .filter { sizeOf($0) > 0 }
            .sorted { sizeOf($0) > sizeOf($1) }
        guard !positiveChildren.isEmpty else { return }

        let total = positiveChildren.reduce(Int64(0)) { $0 &+ sizeOf($1) }
        guard total > 0 else { return }

        switch options.algorithm {
        case .squarified:
            squarify(
                children: positiveChildren,
                totalSize: total,
                container: inner,
                depth: depth &+ 1,
                options: options,
                into: &cells
            )
        case .sliceAndDice:
            sliceAndDice(
                children: positiveChildren,
                totalSize: total,
                container: inner,
                depth: depth &+ 1,
                horizontal: inner.width >= inner.height,
                options: options,
                into: &cells
            )
        }
    }

    // MARK: - Slice and Dice (Shneiderman 1992)

    /// Lay children out along the longer side of the container, each
    /// allocated a strip whose width is proportional to its size.
    /// Recurses into each child with the axis flipped.
    private static func sliceAndDice(
        children: [FSNode],
        totalSize: Int64,
        container: CGRect,
        depth: UInt8,
        horizontal: Bool,
        options: Options,
        into cells: inout [TreemapCell]
    ) {
        let sizeOf = options.sizeMetric.value
        var offset: CGFloat = 0
        for child in children {
            let childSize = sizeOf(child)
            let frac = CGFloat(Double(childSize) / Double(totalSize))
            let span: CGFloat
            let childRect: CGRect
            if horizontal {
                span = container.width * frac
                childRect = CGRect(
                    x: container.minX + offset,
                    y: container.minY,
                    width: span,
                    height: container.height
                )
            } else {
                span = container.height * frac
                childRect = CGRect(
                    x: container.minX,
                    y: container.minY + offset,
                    width: container.width,
                    height: span
                )
            }
            offset += span

            // Don't emit / recurse into degenerate strips.
            guard childRect.width >= options.minLeafEdge, childRect.height >= options.minLeafEdge else { continue }

            cells.append(TreemapCell(
                nodeID: ObjectIdentifier(child),
                rect: childRect,
                depth: depth,
                size: childSize
            ))

            if !child.children.isEmpty, depth < options.maxDepth {
                let inset = options.inset(forDepth: depth)
                let inner = inset > 0 ? childRect.insetBy(dx: inset, dy: inset) : childRect
                guard inner.width > 0, inner.height > 0 else { continue }
                let kids = child.children
                    .filter { sizeOf($0) > 0 }
                    .sorted { sizeOf($0) > sizeOf($1) }
                let inheritedTotal = kids.reduce(Int64(0)) { $0 &+ sizeOf($1) }
                guard !kids.isEmpty, inheritedTotal > 0 else { continue }
                sliceAndDice(
                    children: kids,
                    totalSize: inheritedTotal,
                    container: inner,
                    depth: depth &+ 1,
                    horizontal: !horizontal,
                    options: options,
                    into: &cells
                )
            }
        }
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

        let sizeOf = options.sizeMetric.value
        while index < children.count {
            let shorterSide = min(container.width, container.height)
            guard shorterSide > 0 else { return }

            // Build up a row by greedily appending children while the
            // worst aspect ratio improves (or stays equal). Min/max/sum
            // are tracked as scalars — O(1) per candidate.
            var row: [FSNode] = [children[index]]
            var rowSize = sizeOf(children[index])
            var rowMin = rowSize
            var rowMax = rowSize
            var bestWorst = worst(rowMin: rowMin, rowMax: rowMax,
                                  rowSize: rowSize,
                                  shorterSide: shorterSide)

            var lookahead = index + 1
            while lookahead < children.count {
                let candidate = children[lookahead]
                let candidateSize = sizeOf(candidate)
                let trialSize = rowSize &+ candidateSize
                let trialMin = min(rowMin, candidateSize)
                let trialMax = max(rowMax, candidateSize)
                let trialWorst = worst(rowMin: trialMin, rowMax: trialMax,
                                       rowSize: trialSize,
                                       shorterSide: shorterSide)
                if trialWorst <= bestWorst {
                    row.append(candidate)
                    rowSize = trialSize
                    rowMin = trialMin
                    rowMax = trialMax
                    bestWorst = trialWorst
                    lookahead += 1
                } else {
                    break
                }
            }

            let consumed = lookahead - index
            let firstPlaced = cells.count
            placeRow(
                row: row,
                rowSize: rowSize,
                totalSize: remainingSize,
                container: &container,
                depth: depth,
                options: options,
                sizeOf: sizeOf,
                into: &cells
            )

            // placeRow appended one cell per row element, in order.
            // Snapshot their rects (the array grows during recursion),
            // then recurse into children WITHOUT re-emitting the cell.
            let placed = Array(cells[firstPlaced...])
            for (child, cell) in zip(row, placed) where !child.children.isEmpty {
                recurseChildren(of: child, in: cell.rect, depth: depth, options: options, into: &cells)
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
        sizeOf: (FSNode) -> Int64,
        into cells: inout [TreemapCell]
    ) {
        guard !row.isEmpty, totalSize > 0 else { return }

        let shorterSide = min(container.width, container.height)
        let rowFraction = CGFloat(Double(rowSize) / Double(totalSize))
        let longerSpan = max(container.width, container.height) * rowFraction

        let layoutHorizontally = container.width >= container.height

        var offset: CGFloat = 0
        for child in row {
            let childSize = sizeOf(child)
            let childFraction = CGFloat(Double(childSize) / Double(rowSize))
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
                size: childSize
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
    /// Worst aspect ratio in the row, computed from the running
    /// min/max/sum scalars — O(1) per candidate, no array allocation.
    private static func worst(
        rowMin: Int64,
        rowMax: Int64,
        rowSize: Int64,
        shorterSide: CGFloat
    ) -> Double {
        guard rowMin > 0, rowSize > 0, shorterSide > 0 else { return .infinity }
        let s2 = Double(shorterSide) * Double(shorterSide)
        let rowSum = Double(rowSize)
        let r1 = (Double(rowMax) * s2) / (rowSum * rowSum)
        let r2 = (rowSum * rowSum) / (Double(rowMin) * s2)
        return max(r1, r2)
    }
}
