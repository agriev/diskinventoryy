import AppKit
import UniformTypeIdentifiers

/// Custom `NSView` that draws a treemap from a `TreemapLayout` snapshot.
/// Drawing happens in a single `draw(_:)` pass into the layer's backing
/// store. Adds cushion shading, hover ring, drill-in/drill-out, and
/// drag-out of file URLs.
final class TreemapNSView: NSView, NSDraggingSource {

    // MARK: - Inputs

    var root: FSNode? {
        didSet { rebuildLayout() }
    }

    /// Per-scan kind→color assignment (Disk Inventory X palette,
    /// rank-ordered). Injected by TreemapHost from the environment.
    var kindColors: KindColorMap = .fallback {
        didSet { if oldValue != kindColors { needsDisplay = true } }
    }

    /// 0 = no shading, 1 = strong cushion. Read from AppSettings.
    var cushionIntensity: CGFloat = 0.7 {
        didSet { needsDisplay = true }
    }

    /// 0 = uniform, ~0.4 = strong per-depth darkening.
    var depthContrast: CGFloat = 0.15 {
        didSet { needsDisplay = true }
    }

    /// Whether to size cells by physical (allocated) or logical size.
    var sizeMetric: TreemapLayout.SizeMetric = .physical {
        didSet { rebuildLayout() }
    }

    /// Squarified vs slice-and-dice.
    var algorithm: TreemapLayout.Algorithm = .squarified {
        didSet { rebuildLayout() }
    }

    /// Bumped by the owner after in-place tree mutations (trash,
    /// subtree refresh) — cells and the node index are both stale.
    var treeVersion: Int = 0 {
        didSet { if oldValue != treeVersion { rebuildLayout(force: true) } }
    }

    /// Identity of the FSNode that should be highlighted, if any.
    var selectedNodeID: ObjectIdentifier? {
        didSet { needsDisplay = true }
    }

    /// When non-nil, only cells whose kindID matches stay at full alpha;
    /// everything else fades to ~20%.
    var highlightedKindID: FileKind.ID? {
        didSet { needsDisplay = true }
    }

    /// Notified when the user clicks a cell.
    var onSelect: ((FSNode?) -> Void)?

    /// Notified when the user double-clicks a cell (drill-in request).
    var onDrillIn: ((FSNode) -> Void)?

    /// Notified after the context menu moved a node to the Trash so
    /// the owner can unlink it from the tree.
    var onTrash: ((FSNode) -> Void)?

    // MARK: - State

    private var cells: [TreemapCell] = []
    private var nodeIndex: [ObjectIdentifier: FSNode] = [:]
    private var hoveredNodeID: ObjectIdentifier?
    private var dragStartPoint: CGPoint?
    private var trackingArea: NSTrackingArea?
    private var lastRenderedRoot: ObjectIdentifier?
    /// Cushion gradients are identical for every cell in one pass —
    /// build them once per (intensity, appearance) instead of twice
    /// per cell per frame.
    private var cachedGradients: (key: String, highlight: CGGradient, shadow: CGGradient)?

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
        // During a live window resize the layer scales the last drawn
        // contents — recomputing a 100k-cell layout on every tick just
        // burns the main thread. Exact layout lands on settle.
        if inLiveResize {
            needsDisplay = true
        } else {
            rebuildLayout()
        }
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        rebuildLayout()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// Recompute cell rects. The node index — a full-tree walk — is
    /// only rebuilt when the root identity or the tree contents
    /// changed, never on plain resizes.
    func rebuildLayout(force: Bool = false) {
        guard let root, bounds.width > 0, bounds.height > 0 else {
            cells = []
            nodeIndex = [:]
            lastRenderedRoot = nil
            needsDisplay = true
            return
        }
        var options = TreemapLayout.Options.default
        options.sizeMetric = sizeMetric
        options.algorithm = algorithm
        cells = TreemapLayout.layout(root: root, bounds: bounds, options: options)

        let newRootID = ObjectIdentifier(root)
        if force || newRootID != lastRenderedRoot {
            rebuildNodeIndex(root: root)
        }
        needsDisplay = true

        // Crossfade when the root identity changes — drill-in,
        // drill-out, or a fresh scan. Skip when the user has Reduce
        // Motion enabled or layer isn't available.
        if let last = lastRenderedRoot, last != newRootID,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           let layer {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue = 1.0
            fade.duration = 0.22
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(fade, forKey: "treemap-drill-fade")
        }
        lastRenderedRoot = newRootID
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

        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(dirtyRect)

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        let highlight = highlightedKindID
        let cushion = !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

        // Disk Inventory X convention: kind colors belong to FILES only.
        // Directories are implicit grouping — a neutral tone that shows
        // through as thin frames around their children. Painting
        // directories with a kind color (they'd all be "Other" yellow)
        // is what makes a treemap read as meaningless flat blocks.
        let dirFill = isDark
            ? NSColor(white: 0.24, alpha: 1.0)
            : NSColor(white: 0.80, alpha: 1.0)

        for cell in cells {
            guard cell.depth > 0 else { continue }
            guard cell.rect.intersects(dirtyRect) else { continue }
            guard let node = nodeIndex[cell.nodeID] else { continue }

            // Packages scanned without descendIntoPackages carry their
            // totals but no children — draw them as colored leaves of
            // their kind (DIX does the same), not as empty dir frames.
            let isLeafCell = !node.isContainer || node.children.isEmpty
            let dimmed = highlight != nil && (!isLeafCell || node.kindID != highlight)

            if isLeafCell {
                let baseColor = kindColors.nsColor(for: node.kindID)
                // Dim by blending toward the background opaquely — an
                // alpha fill would composite over whatever was painted
                // underneath (the parent frame) instead of receding.
                let finalColor = dimmed
                    ? (baseColor.blended(withFraction: 0.85, of: dirFill) ?? baseColor)
                    : baseColor
                context.setFillColor(finalColor.cgColor)
                context.fill(cell.rect)

                if cushion, !dimmed, cushionIntensity > 0.01,
                   cell.rect.width >= 3, cell.rect.height >= 3 {
                    drawCushion(in: cell.rect, context: context, isDark: isDark)
                }
                if node.isSynthetic, cell.rect.width >= 40, cell.rect.height >= 16 {
                    drawSyntheticLabel(for: node, in: cell.rect, context: context, isDark: isDark)
                }
            } else {
                // Directory: neutral, slightly darker per depth so the
                // nesting frames stay readable.
                let fill = colorAdjustedForDepth(dirFill, depth: cell.depth, isDark: isDark)
                context.setFillColor((dimmed ? fill.withAlphaComponent(0.3) : fill).cgColor)
                context.fill(cell.rect)
            }

            if cell.rect.width >= 4 && cell.rect.height >= 4 {
                context.setStrokeColor(NSColor.black.withAlphaComponent(isDark ? 0.35 : 0.22).cgColor)
                context.setLineWidth(0.5)
                context.stroke(cell.rect.insetBy(dx: 0.25, dy: 0.25))
            }
        }

        // Hover: lighten the hovered cell — much easier to spot than a
        // hairline ring, and mirrors DIX's hover feedback.
        if let hoveredNodeID,
           let cell = cells.last(where: { $0.nodeID == hoveredNodeID && $0.depth > 0 }) {
            context.setFillColor(NSColor.white.withAlphaComponent(isDark ? 0.18 : 0.28).cgColor)
            context.setBlendMode(.plusLighter)
            context.fill(cell.rect)
            context.setBlendMode(.normal)
            context.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(1)
            context.stroke(cell.rect.insetBy(dx: 0.5, dy: 0.5))
        }

        // Selection ring. Drawn entirely *inside* the cell rect (insets
        // 3pt) so it doesn't clip at the edge of the treemap view.
        // Two-layer: dark halo behind, accent on top, so the ring
        // stays visible regardless of cell colour or cushion shading.
        if let selectedNodeID,
           let cell = cells.first(where: { $0.nodeID == selectedNodeID && $0.depth > 0 }) {
            let inset: CGFloat = min(3, min(cell.rect.width, cell.rect.height) / 4)
            guard inset > 0 else { return }
            let rect = cell.rect.insetBy(dx: inset, dy: inset)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(3.5)
            context.stroke(rect)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(2)
            context.stroke(rect)
        }
    }

    /// Two-pass pillow shading approximating the Bruls/van Wijk cushion
    /// treemap: a `.plusLighter` highlight falling from the top-left and
    /// a `.multiply` shadow toward the bottom-right. Reads as the
    /// classic Disk Inventory X 3-D pillow without per-pixel work.
    private func drawCushion(in rect: CGRect, context: CGContext, isDark: Bool) {
        guard let (hi, lo) = cushionGradients(isDark: isDark) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect)

        let start = CGPoint(x: rect.minX, y: rect.minY)
        let end = CGPoint(x: rect.maxX, y: rect.maxY)
        context.setBlendMode(.plusLighter)
        context.drawLinearGradient(hi, start: start, end: end, options: [])
        context.setBlendMode(.multiply)
        context.drawLinearGradient(lo, start: start, end: end, options: [])
    }

    private func cushionGradients(isDark: Bool) -> (CGGradient, CGGradient)? {
        let key = "\(isDark)-\(cushionIntensity)"
        if let cached = cachedGradients, cached.key == key {
            return (cached.highlight, cached.shadow)
        }
        let strength = cushionIntensity
        let space = CGColorSpaceCreateDeviceRGB()
        let hiAlpha = (isDark ? 0.22 : 0.34) * strength
        let shadowDepth = (isDark ? 0.30 : 0.38) * strength
        guard
            let hi = CGGradient(
                colorsSpace: space,
                colors: [
                    NSColor(white: 1.0, alpha: hiAlpha).cgColor,
                    NSColor(white: 1.0, alpha: 0.0).cgColor,
                ] as CFArray,
                locations: [0, 0.55]
            ),
            let lo = CGGradient(
                colorsSpace: space,
                colors: [
                    NSColor(white: 1.0, alpha: 1.0).cgColor,
                    NSColor(white: 1.0 - shadowDepth, alpha: 1.0).cgColor,
                ] as CFArray,
                locations: [0.45, 1]
            )
        else { return nil }
        cachedGradients = (key, hi, lo)
        return (hi, lo)
    }

    /// Free space / Other space cells get an inline caption when big
    /// enough — grey blocks with no label would read as a bug.
    private func drawSyntheticLabel(for node: FSNode, in rect: CGRect, context: CGContext, isDark: Bool) {
        let text = "\(node.displayName) — \(ByteFormatter.format(node.physicalSize))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: isDark ? NSColor(white: 0.75, alpha: 1) : NSColor(white: 0.35, alpha: 1),
        ]
        let size = text.size(withAttributes: attributes)
        guard size.width <= rect.width - 8 else {
            let short = node.displayName as NSString
            let shortSize = short.size(withAttributes: attributes)
            if shortSize.width <= rect.width - 8 {
                short.draw(
                    at: CGPoint(x: rect.midX - shortSize.width / 2, y: rect.midY - shortSize.height / 2),
                    withAttributes: attributes
                )
            }
            return
        }
        text.draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func colorAdjustedForDepth(_ color: NSColor, depth: UInt8, isDark: Bool) -> NSColor {
        // Per-depth darkening proportional to user-controlled contrast.
        let perDepth = depthContrast / 3.0
        let attenuation = min(CGFloat(depth) * perDepth, depthContrast)
        let factor: CGFloat = isDark ? (1.0 - attenuation * 0.5) : (1.0 - attenuation)
        let resolved = color.usingColorSpace(.deviceRGB) ?? color
        return NSColor(
            deviceRed: resolved.redComponent * factor,
            green: resolved.greenComponent * factor,
            blue: resolved.blueComponent * factor,
            alpha: resolved.alphaComponent
        )
    }

    // MARK: - Mouse events

    override func mouseEntered(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredNodeID != nil {
            hoveredNodeID = nil
            needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    private func updateHover(at point: CGPoint) {
        let hit = hitTestCell(at: point)
        let newID = hit.map(ObjectIdentifier.init)
        guard newID != hoveredNodeID else { return }

        // Invalidate only the union of the previous and next hovered
        // cells; the intersects(dirtyRect) cull in draw() keeps the
        // repaint to a handful of cells instead of the whole map.
        let oldRect = hoveredNodeID.flatMap { id in
            cells.last(where: { $0.nodeID == id && $0.depth > 0 })?.rect
        }
        hoveredNodeID = newID
        let newRect = newID.flatMap { id in
            cells.last(where: { $0.nodeID == id && $0.depth > 0 })?.rect
        }
        switch (oldRect, newRect) {
        case let (old?, new?): setNeedsDisplay(old.union(new).insetBy(dx: -2, dy: -2))
        case let (old?, nil):  setNeedsDisplay(old.insetBy(dx: -2, dy: -2))
        case let (nil, new?):  setNeedsDisplay(new.insetBy(dx: -2, dy: -2))
        default: break
        }
        toolTip = hit.map(Self.tooltipText(for:))
    }

    /// Multi-line tooltip with name, size, kind and the full path so
    /// users can reason about what they're hovering without clicking.
    private static func tooltipText(for node: FSNode) -> String {
        let kindLabel = node.kindID.capitalized
        let physical = ByteFormatter.format(node.physicalSize)
        let logical = ByteFormatter.format(node.logicalSize)
        var lines: [String] = [node.displayName]
        if node.physicalSize != node.logicalSize {
            lines.append("\(physical) on disk · \(logical) logical · \(kindLabel)")
        } else {
            lines.append("\(physical) · \(kindLabel)")
        }
        lines.append(node.url.path)
        return lines.joined(separator: "\n")
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let hit = hitTestCell(at: local)
        onSelect?(hit)
        if let hit { selectedNodeID = ObjectIdentifier(hit) }

        if event.clickCount >= 2 {
            // Cancel any pending drag started by the previous mouseDown
            // so a stray pointer movement between clicks doesn't kick
            // off a drag-out and have the dropped URL re-open as a
            // new scan window.
            dragStartPoint = nil
            if let hit {
                let target: FSNode? = {
                    if hit.isContainer { return hit }
                    var cursor = hit.parent
                    while let node = cursor {
                        if node.isContainer { return node }
                        cursor = node.parent
                    }
                    return nil
                }()
                if let target { onDrillIn?(target) }
            }
        } else {
            dragStartPoint = local
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let local = convert(event.locationInWindow, from: nil)
        guard let hit = hitTestCell(at: local) else { return nil }
        // Surface the right-clicked cell as the selection so the
        // treemap reflects what the menu is acting on.
        onSelect?(hit)
        selectedNodeID = ObjectIdentifier(hit)
        return ItemContextMenu.make(for: hit, onTrash: onTrash)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartPoint else { return }
        let here = convert(event.locationInWindow, from: nil)
        let dx = here.x - start.x
        let dy = here.y - start.y
        guard dx * dx + dy * dy > 16 else { return }   // 4 pt deadzone

        guard let selectedNodeID,
              let node = nodeIndex[selectedNodeID],
              !node.isSynthetic else {
            return
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(node.url.absoluteString, forType: .fileURL)
        pasteboardItem.setString(node.url.path, forType: .string)

        let dragItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        if let cell = cells.first(where: { $0.nodeID == selectedNodeID && $0.depth > 0 }) {
            dragItem.draggingFrame = cell.rect
            dragItem.imageComponentsProvider = { [weak self] in
                guard let self else { return [] }
                let component = NSDraggingImageComponent(key: .icon)
                component.contents = self.snapshotImage(of: cell.rect, for: node)
                component.frame = CGRect(origin: .zero, size: cell.rect.size)
                return [component]
            }
        }
        beginDraggingSession(with: [dragItem], event: event, source: self)
        dragStartPoint = nil
    }

    private func snapshotImage(of rect: CGRect, for node: FSNode) -> NSImage {
        let size = rect.size
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let context = NSGraphicsContext.current?.cgContext else { return image }
        let baseColor = kindColors.nsColor(for: node.kindID).withAlphaComponent(0.85)
        context.setFillColor(baseColor.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        context.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))
        return image
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch context {
        case .outsideApplication: return [.copy, .link]
        case .withinApplication:  return [.copy]
        @unknown default:         return [.copy]
        }
    }

    // MARK: - Hit testing

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
