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

    var palette: ColorPalette = .shared {
        didSet { needsDisplay = true }
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

    // MARK: - State

    private var cells: [TreemapCell] = []
    private var nodeIndex: [ObjectIdentifier: FSNode] = [:]
    private var hoveredNodeID: ObjectIdentifier?
    private var dragStartPoint: CGPoint?
    private var trackingArea: NSTrackingArea?

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

    private func rebuildLayout() {
        guard let root, bounds.width > 0, bounds.height > 0 else {
            cells = []
            nodeIndex = [:]
            needsDisplay = true
            return
        }
        var options = TreemapLayout.Options.default
        options.sizeMetric = sizeMetric
        options.algorithm = algorithm
        cells = TreemapLayout.layout(root: root, bounds: bounds, options: options)
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

        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(dirtyRect)

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        let highlight = highlightedKindID
        let cushion = !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

        for cell in cells {
            guard cell.depth > 0 else { continue }
            guard cell.rect.intersects(dirtyRect) else { continue }
            guard let node = nodeIndex[cell.nodeID] else { continue }

            let dimmed = highlight != nil && node.kindID != highlight
            let baseColor = palette.nsColor(for: node.kindID)
            let depthAdjusted = colorAdjustedForDepth(baseColor, depth: cell.depth, isDark: isDark)
            let finalColor = dimmed
                ? depthAdjusted.withAlphaComponent(0.18)
                : depthAdjusted

            context.setFillColor(finalColor.cgColor)
            context.fill(cell.rect)

            if cushion, !dimmed, cushionIntensity > 0.01, cell.rect.width >= 6, cell.rect.height >= 6 {
                drawCushion(in: cell.rect, context: context, isDark: isDark)
            }

            if cell.rect.width >= 4 && cell.rect.height >= 4 {
                context.setStrokeColor(NSColor.black.withAlphaComponent(isDark ? 0.30 : 0.18).cgColor)
                context.setLineWidth(0.5)
                context.stroke(cell.rect.insetBy(dx: 0.25, dy: 0.25))
            }
        }

        // Hover ring (drawn before selection so selection wins).
        if let hoveredNodeID,
           let cell = cells.first(where: { $0.nodeID == hoveredNodeID && $0.depth > 0 }) {
            context.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.4).cgColor)
            context.setLineWidth(1)
            context.stroke(cell.rect.insetBy(dx: 0.5, dy: 0.5))
        }

        // Selection ring.
        if let selectedNodeID,
           let cell = cells.first(where: { $0.nodeID == selectedNodeID && $0.depth > 0 }) {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(2)
            context.stroke(cell.rect.insetBy(dx: 1, dy: 1))
        }
    }

    /// Top-left → bottom-right linear gradient via `.multiply`. Cheap
    /// approximation of the Bruls/van Wijk cushion treemap; reads as
    /// gentle 3-D shading without per-pixel work.
    private func drawCushion(in rect: CGRect, context: CGContext, isDark: Bool) {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect)
        context.setBlendMode(.multiply)
        let baseIntensity: CGFloat = isDark ? 0.10 : 0.18
        let intensity = baseIntensity * cushionIntensity
        let colors = [
            NSColor(white: 1.0, alpha: 1.0 - intensity * 0.5).cgColor,
            NSColor(white: 1.0 - intensity, alpha: 1.0).cgColor,
        ]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0, 1]
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: []
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
        if newID != hoveredNodeID {
            hoveredNodeID = newID
            needsDisplay = true
            toolTip = hit.map(Self.tooltipText(for:))
        }
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
        let baseColor = palette.nsColor(for: node.kindID).withAlphaComponent(0.85)
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
