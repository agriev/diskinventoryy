import AppKit

/// Custom `NSView` that draws a treemap from a `TreemapLayout` snapshot.
/// Drawing happens in a single `draw(_:)` pass into the layer's backing
/// store; SwiftUI/AppKit transparency hits stay constant regardless of
/// cell count.
final class TreemapNSView: NSView {

    // MARK: - Inputs

    var root: FSNode? {
        didSet { rebuildLayout() }
    }

    var palette: ColorPalette = .shared {
        didSet { needsDisplay = true }
    }

    /// Identity of the FSNode that should be highlighted, if any.
    var selectedNodeID: ObjectIdentifier? {
        didSet { needsDisplay = true }
    }

    /// Notified when the user clicks a cell. Receives the `FSNode` at
    /// the click point or `nil` when the click landed outside any cell.
    var onSelect: ((FSNode?) -> Void)?

    // MARK: - State

    private var cells: [TreemapCell] = []
    /// Resolves a cell's `nodeID` back to its `FSNode`. We hold strong
    /// references so the algorithm output remains addressable while the
    /// view lives.
    private var nodeIndex: [ObjectIdentifier: FSNode] = [:]

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    override var isFlipped: Bool { true }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rebuildLayout()
    }

    private func rebuildLayout() {
        guard let root, bounds.width > 0, bounds.height > 0 else {
            cells = []
            nodeIndex = [:]
            needsDisplay = true
            return
        }
        cells = TreemapLayout.layout(
            root: root,
            bounds: bounds,
            options: TreemapLayout.Options.default
        )
        rebuildNodeIndex(root: root)
        needsDisplay = true
    }

    private func rebuildNodeIndex(root: FSNode) {
        nodeIndex.removeAll(keepingCapacity: true)
        var stack: [FSNode] = [root]
        while let node = stack.popLast() {
            nodeIndex[ObjectIdentifier(node)] = node
            stack.append(contentsOf: node.children)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        // Background.
        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(dirtyRect)

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil

        for cell in cells {
            guard cell.depth > 0 else { continue }
            guard cell.rect.intersects(dirtyRect) else { continue }
            guard let node = nodeIndex[cell.nodeID] else { continue }

            let baseColor = palette.nsColor(for: node.kindID)
            let depthAdjusted = colorAdjustedForDepth(baseColor, depth: cell.depth, isDark: isDark)

            context.setFillColor(depthAdjusted.cgColor)
            context.fill(cell.rect)

            // Subtle border to separate cells of the same kind.
            if cell.rect.width >= 4 && cell.rect.height >= 4 {
                context.setStrokeColor(NSColor.black.withAlphaComponent(0.18).cgColor)
                context.setLineWidth(0.5)
                context.stroke(cell.rect.insetBy(dx: 0.25, dy: 0.25))
            }
        }

        // Selection overlay: drawn last so it sits above the fills.
        if let selectedNodeID,
           let cell = cells.first(where: { $0.nodeID == selectedNodeID && $0.depth > 0 }) {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(2)
            let inset: CGFloat = 1
            context.stroke(cell.rect.insetBy(dx: inset, dy: inset))
        }
    }

    private func colorAdjustedForDepth(_ color: NSColor, depth: UInt8, isDark: Bool) -> NSColor {
        // Each level darkens slightly so nested folders are visually
        // distinguishable from their parent of the same kind.
        let darkenStep: CGFloat = 0.05
        let attenuation = min(CGFloat(depth) * darkenStep, 0.4)
        let factor: CGFloat = isDark ? (1.0 - attenuation * 0.5) : (1.0 - attenuation)
        let resolved = color.usingColorSpace(.deviceRGB) ?? color
        return NSColor(
            deviceRed: resolved.redComponent * factor,
            green: resolved.greenComponent * factor,
            blue: resolved.blueComponent * factor,
            alpha: resolved.alphaComponent
        )
    }

    // MARK: - Hit testing

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let hit = hitTestCell(at: local)
        onSelect?(hit)
        if let hit { selectedNodeID = ObjectIdentifier(hit) }
    }

    /// Find the deepest cell that contains `point`. Walks the cell list
    /// in reverse so leaves win over their ancestor parent rects.
    private func hitTestCell(at point: CGPoint) -> FSNode? {
        for cell in cells.reversed() {
            if cell.depth > 0, cell.rect.contains(point) {
                return nodeIndex[cell.nodeID]
            }
        }
        return nil
    }

    // MARK: - Accessibility

    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? {
        guard let root else { return "Empty treemap" }
        return "Treemap of \(root.displayName)"
    }
}
