import Foundation

/// A single node in the scanned filesystem tree.
///
/// Reference type by design: weak parent pointers are not expressible on
/// values, copying a 10M-node tree by value would be unacceptable, and
/// SwiftUI views diff cheaply by `ObjectIdentifier`. Mutability is
/// confined to the owning `Scanner` actor or to `@MainActor` view models;
/// hence the `@unchecked Sendable` conformance.
final class FSNode: Identifiable, Hashable, @unchecked Sendable {
    let url: URL
    var displayName: String
    var kind: FSNodeKind
    var fileType: FileType
    var logicalSize: Int64
    var physicalSize: Int64
    var itemCount: Int32
    weak var parent: FSNode?
    private(set) var children: [FSNode]
    var kindID: FileKind.ID
    var isPackage: Bool
    var isMountPoint: Bool
    var depth: UInt8
    var mtime: Date?
    var flags: FSFlags
    var errors: [ScanError]?

    init(
        url: URL,
        displayName: String? = nil,
        kind: FSNodeKind = .regular,
        fileType: FileType = .regularFile,
        logicalSize: Int64 = 0,
        physicalSize: Int64 = 0,
        itemCount: Int32 = 0,
        parent: FSNode? = nil,
        children: [FSNode] = [],
        kindID: FileKind.ID = FileKind.other.id,
        isPackage: Bool = false,
        isMountPoint: Bool = false,
        depth: UInt8 = 0,
        mtime: Date? = nil,
        flags: FSFlags = []
    ) {
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.kind = kind
        self.fileType = fileType
        self.logicalSize = logicalSize
        self.physicalSize = physicalSize
        self.itemCount = itemCount
        self.parent = parent
        self.children = children
        self.kindID = kindID
        self.isPackage = isPackage
        self.isMountPoint = isMountPoint
        self.depth = depth
        self.mtime = mtime
        self.flags = flags
    }

    // MARK: Identity / equality

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    static func == (lhs: FSNode, rhs: FSNode) -> Bool { lhs === rhs }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    // MARK: Tree mutations

    /// True when this node represents a directory-like container that
    /// should be expanded in the outline by default. Synthetic nodes
    /// (free / other space) are leaves.
    var isContainer: Bool {
        switch fileType {
        case .directory, .package, .mountPoint:
            return true
        default:
            return false
        }
    }

    /// Whether this node is a synthetic placeholder (not a real file).
    var isSynthetic: Bool { kind != .regular }

    /// Append a child and propagate sizes/leaf counts up the tree.
    /// `itemCount` semantics: total file leaves underneath the node.
    /// Files start at 1, directories start at 0 and accumulate.
    func appendChild(_ child: FSNode) {
        child.parent = self
        child.depth = depth &+ 1
        children.append(child)
        propagateAdd(logical: child.logicalSize,
                     physical: child.physicalSize,
                     itemCount: child.itemCount)
    }

    /// Remove a child by identity. Sizes and counts bubble back up.
    @discardableResult
    func removeChild(_ child: FSNode) -> Bool {
        guard let index = children.firstIndex(where: { $0 === child }) else {
            return false
        }
        let removed = children.remove(at: index)
        removed.parent = nil
        propagateAdd(logical: -removed.logicalSize,
                     physical: -removed.physicalSize,
                     itemCount: -removed.itemCount)
        return true
    }

    /// Replace the children array atomically. Used by subtree refresh
    /// where size deltas are computed against the old subtree.
    func replaceChildren(_ newChildren: [FSNode]) {
        let oldLogical = children.reduce(Int64(0)) { $0 + $1.logicalSize }
        let oldPhysical = children.reduce(Int64(0)) { $0 + $1.physicalSize }
        let oldCount: Int32 = children.reduce(0) { $0 + $1.itemCount }

        for child in children where child.parent === self {
            child.parent = nil
        }
        children = newChildren

        var newLogical: Int64 = 0
        var newPhysical: Int64 = 0
        var newCount: Int32 = 0
        for child in newChildren {
            child.parent = self
            child.depth = depth &+ 1
            newLogical += child.logicalSize
            newPhysical += child.physicalSize
            newCount += child.itemCount
        }

        propagateAdd(
            logical: newLogical - oldLogical,
            physical: newPhysical - oldPhysical,
            itemCount: newCount - oldCount
        )
    }

    /// Path from the root to this node, inclusive.
    var ancestry: [FSNode] {
        var chain: [FSNode] = []
        var cursor: FSNode? = self
        while let node = cursor {
            chain.append(node)
            cursor = node.parent
        }
        return chain.reversed()
    }

    // MARK: - Internals

    private func propagateAdd(logical: Int64, physical: Int64, itemCount: Int32) {
        guard logical != 0 || physical != 0 || itemCount != 0 else { return }
        var cursor: FSNode? = self
        while let node = cursor {
            node.logicalSize &+= logical
            node.physicalSize &+= physical
            node.itemCount &+= itemCount
            cursor = node.parent
        }
    }
}
