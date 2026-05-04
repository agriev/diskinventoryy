import AppKit
import SwiftUI

/// SwiftUI host for an `NSOutlineView`. Gives us cell reuse, multi-
/// column sorting, and acceptable performance on 100K+ rows where
/// SwiftUI's `OutlineGroup` starts to skip frames.
struct OutlineHost: NSViewRepresentable {
    let root: FSNode
    @Binding var selectedNode: FSNode?
    var sortDescriptors: [NSSortDescriptor] = [
        NSSortDescriptor(key: "size", ascending: false)
    ]

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: OutlineHost
        weak var outlineView: NSOutlineView?
        var sortedChildrenCache: [ObjectIdentifier: [FSNode]] = [:]
        var currentSort: [NSSortDescriptor] = []

        init(_ parent: OutlineHost) {
            self.parent = parent
            self.currentSort = parent.sortDescriptors
        }

        func sortedChildren(of node: FSNode) -> [FSNode] {
            if let cached = sortedChildrenCache[ObjectIdentifier(node)] { return cached }
            let sorted = node.children.sorted(by: comparator(currentSort))
            sortedChildrenCache[ObjectIdentifier(node)] = sorted
            return sorted
        }

        private func comparator(_ descriptors: [NSSortDescriptor]) -> (FSNode, FSNode) -> Bool {
            let primary = descriptors.first ?? NSSortDescriptor(key: "size", ascending: false)
            return { a, b in
                switch primary.key {
                case "name":
                    let cmp = a.displayName.localizedStandardCompare(b.displayName)
                    return primary.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
                case "kind":
                    let cmp = a.kindID.compare(b.kindID)
                    return primary.ascending ? cmp == .orderedAscending : cmp == .orderedDescending
                case "modified":
                    let lhs = a.mtime ?? .distantPast
                    let rhs = b.mtime ?? .distantPast
                    return primary.ascending ? lhs < rhs : lhs > rhs
                default: // size
                    return primary.ascending
                        ? a.physicalSize < b.physicalSize
                        : a.physicalSize > b.physicalSize
                }
            }
        }

        // MARK: NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return 1   // wrapping single root
            }
            guard let node = item as? FSNode else { return 0 }
            return node.isContainer ? sortedChildren(of: node).count : 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil { return parent.root }
            let node = item as! FSNode
            return sortedChildren(of: node)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FSNode)?.isContainer ?? false
        }

        // MARK: NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let column = tableColumn, let node = item as? FSNode else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("Cell-\(column.identifier.rawValue)")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: nil) as? OutlineCellView)
                ?? OutlineCellView(identifier: identifier)

            switch column.identifier.rawValue {
            case "name":
                cell.imageView?.image = IconCache.shared.icon(for: node)
                cell.swatch.fillColor = ColorPalette.shared.nsColor(for: node.kindID)
                cell.textField?.stringValue = node.displayName
            case "size":
                cell.textField?.stringValue = ByteFormatter.format(node.physicalSize)
                cell.textField?.alignment = .right
            case "kind":
                cell.textField?.stringValue = node.kindID.capitalized
            case "modified":
                if let mtime = node.mtime {
                    cell.textField?.stringValue = mtime.formatted(.dateTime.year().month().day())
                } else {
                    cell.textField?.stringValue = "—"
                }
            default:
                cell.textField?.stringValue = ""
            }
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let row = outlineView.selectedRow
            let node = row >= 0 ? outlineView.item(atRow: row) as? FSNode : nil
            DispatchQueue.main.async {
                self.parent.selectedNode = node
            }
        }

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            currentSort = outlineView.sortDescriptors
            sortedChildrenCache.removeAll()
            outlineView.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.usesAlternatingRowBackgroundColors = true
        outline.usesAutomaticRowHeights = true
        outline.style = .inset
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = true
        outline.headerView = NSTableHeaderView()
        outline.indentationPerLevel = 14

        addColumns(to: outline)
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.sortDescriptors = sortDescriptors
        context.coordinator.outlineView = outline

        let scrollView = NSScrollView()
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        outline.expandItem(root)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outline = scrollView.documentView as? NSOutlineView else { return }
        // If the root changed, rebind data source content.
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.currentSort != sortDescriptors {
            coordinator.currentSort = sortDescriptors
            outline.sortDescriptors = sortDescriptors
            coordinator.sortedChildrenCache.removeAll()
        }
        outline.reloadData()
        outline.expandItem(root)

        // Sync selection from binding back into the outline.
        if let node = selectedNode {
            // Expand all ancestors so the row exists in the visible
            // tree. NSOutlineView.row(forItem:) only finds rows that
            // are currently exposed.
            for ancestor in node.ancestry where ancestor !== node {
                if !outline.isItemExpanded(ancestor) {
                    outline.expandItem(ancestor)
                }
            }
            let row = outline.row(forItem: node)
            if row >= 0 {
                if outline.selectedRow != row {
                    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
                outline.scrollRowToVisible(row)
            }
        } else if outline.selectedRow >= 0 {
            outline.deselectAll(nil)
        }
    }

    private func addColumns(to outline: NSOutlineView) {
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Name"
        nameCol.minWidth = 180
        nameCol.width = 320
        nameCol.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        outline.addTableColumn(nameCol)
        outline.outlineTableColumn = nameCol

        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "Size"
        sizeCol.minWidth = 80
        sizeCol.width = 110
        sizeCol.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: false)
        outline.addTableColumn(sizeCol)

        let kindCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindCol.title = "Kind"
        kindCol.minWidth = 80
        kindCol.width = 110
        kindCol.sortDescriptorPrototype = NSSortDescriptor(key: "kind", ascending: true)
        outline.addTableColumn(kindCol)

        let mtimeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("modified"))
        mtimeCol.title = "Modified"
        mtimeCol.minWidth = 100
        mtimeCol.width = 130
        mtimeCol.sortDescriptorPrototype = NSSortDescriptor(key: "modified", ascending: false)
        outline.addTableColumn(mtimeCol)
    }
}

/// Cell with a colored swatch + image + text. Reused across all columns.
final class OutlineCellView: NSTableCellView {
    let swatch = SwatchLayerView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = .byTruncatingMiddle
        text.cell?.usesSingleLineMode = true
        swatch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatch)
        addSubview(icon)
        addSubview(text)
        NSLayoutConstraint.activate([
            swatch.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            swatch.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatch.widthAnchor.constraint(equalToConstant: 8),
            swatch.heightAnchor.constraint(equalToConstant: 8),
            icon.leadingAnchor.constraint(equalTo: swatch.trailingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        self.imageView = icon
        self.textField = text
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

final class SwatchLayerView: NSView {
    var fillColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        fillColor.setFill()
        bounds.fill()
    }
}
