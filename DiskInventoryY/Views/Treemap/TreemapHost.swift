import SwiftUI
import AppKit

/// Bridges the AppKit-backed `TreemapNSView` into SwiftUI.
struct TreemapHost: NSViewRepresentable {
    let root: FSNode
    @Binding var selectedNode: FSNode?
    var highlightedKind: FileKind.ID?
    var cushionIntensity: Double = 0.7
    var depthContrast: Double = 0.15
    var sizeMetric: TreemapLayout.SizeMetric = .physical
    var algorithm: TreemapLayout.Algorithm = .squarified
    var onDrillIn: ((FSNode) -> Void)? = nil

    func makeNSView(context: Context) -> TreemapNSView {
        let view = TreemapNSView()
        view.root = root
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
    }
}
