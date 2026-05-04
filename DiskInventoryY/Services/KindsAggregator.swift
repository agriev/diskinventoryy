import Foundation

/// One row in the Kinds bar: total bytes contributed by every leaf with
/// a given `kindID`, plus the file count for a tooltip.
struct KindAggregate: Identifiable, Sendable, Hashable {
    let id: FileKind.ID
    var displayName: String
    var totalLogical: Int64
    var totalPhysical: Int64
    var fileCount: Int32
}

/// Produces ordered `KindAggregate`s from a tree. Pure function —
/// callers run it once after a scan and any time the tree mutates.
enum KindsAggregator {
    static func aggregate(_ root: FSNode) -> [KindAggregate] {
        var totals: [FileKind.ID: KindAggregate] = [:]
        var stack: [FSNode] = [root]
        while let node = stack.popLast() {
            // Only files contribute. Directories aggregate via their
            // descendants; synthetic Free / Other space stays neutral.
            if node.fileType == .regularFile || node.fileType == .package {
                let id = node.kindID
                let display = totals[id]?.displayName ?? Self.displayName(for: id)
                let existing = totals[id]
                totals[id] = KindAggregate(
                    id: id,
                    displayName: display,
                    totalLogical: (existing?.totalLogical ?? 0) &+ node.logicalSize,
                    totalPhysical: (existing?.totalPhysical ?? 0) &+ node.physicalSize,
                    fileCount: (existing?.fileCount ?? 0) &+ 1
                )
            }
            stack.append(contentsOf: node.children)
        }
        return totals.values.sorted { $0.totalPhysical > $1.totalPhysical }
    }

    private static func displayName(for id: FileKind.ID) -> String {
        if let known = FileKind.allKnown.first(where: { $0.id == id }) {
            return known.displayName
        }
        return id.capitalized
    }
}
