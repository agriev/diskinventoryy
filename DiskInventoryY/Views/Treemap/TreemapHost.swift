import SwiftUI
import AppKit

/// Bridges the AppKit-backed `TreemapNSView` into SwiftUI.
struct TreemapHost: NSViewRepresentable {
    let root: FSNode
    @Binding var selectedNode: FSNode?

    func makeNSView(context: Context) -> TreemapNSView {
        let view = TreemapNSView()
        view.root = root
        view.onSelect = { node in
            DispatchQueue.main.async {
                self.selectedNode = node
            }
        }
        return view
    }

    func updateNSView(_ nsView: TreemapNSView, context: Context) {
        if nsView.root !== root {
            nsView.root = root
        }
        nsView.selectedNodeID = selectedNode.map(ObjectIdentifier.init)
    }
}
