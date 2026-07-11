import SwiftUI
import AppKit

/// Bridges the AppKit-backed `TreemapNSView` into SwiftUI.
struct TreemapHost: NSViewRepresentable {
    let root: FSNode
    @Binding var selectedNode: FSNode?
    var highlightedKind: FileKind.ID?
    var treeVersion: Int = 0
    var cushionIntensity: Double = 0.7
    var depthContrast: Double = 0.15
    var sizeMetric: TreemapLayout.SizeMetric = .physical
    var algorithm: TreemapLayout.Algorithm = .squarified
    var onDrillIn: ((FSNode) -> Void)? = nil
    var onTrash: ((FSNode) -> Void)? = nil
    @Environment(\.kindColors) private var kindColors

    func makeNSView(context: Context) -> TreemapNSView {
        let view = TreemapNSView()
        view.root = root
        view.kindColors = kindColors
        view.cushionIntensity = CGFloat(cushionIntensity)
        view.depthContrast = CGFloat(depthContrast)
        view.sizeMetric = sizeMetric
        view.algorithm = algorithm
        view.onSelect = { node in
            DispatchQueue.main.async {
                self.selectedNode = node
            }
        }
        view.onDrillIn = { node in
            DispatchQueue.main.async {
                self.onDrillIn?(node)
            }
        }
        view.onTrash = { node in
            DispatchQueue.main.async {
                self.onTrash?(node)
            }
        }
        return view
    }

    func updateNSView(_ nsView: TreemapNSView, context: Context) {
        if nsView.root !== root {
            nsView.root = root
        }
        if nsView.sizeMetric != sizeMetric {
            nsView.sizeMetric = sizeMetric
        }
        if nsView.algorithm != algorithm {
            nsView.algorithm = algorithm
        }
        nsView.kindColors = kindColors
        nsView.treeVersion = treeVersion
        nsView.cushionIntensity = CGFloat(cushionIntensity)
        nsView.depthContrast = CGFloat(depthContrast)
        nsView.selectedNodeID = selectedNode.map(ObjectIdentifier.init)
        nsView.highlightedKindID = highlightedKind
        // Keep the closures fresh in case the parent's binding changed.
        nsView.onSelect = { node in
            DispatchQueue.main.async {
                self.selectedNode = node
            }
        }
        nsView.onDrillIn = { node in
            DispatchQueue.main.async {
                self.onDrillIn?(node)
            }
        }
        nsView.onTrash = { node in
            DispatchQueue.main.async {
                self.onTrash?(node)
            }
        }
    }
}
