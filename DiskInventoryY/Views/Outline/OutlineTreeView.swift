import SwiftUI

/// Temporary SwiftUI-only outline. Replaces the empty state once a scan
/// finishes. Will be swapped for an `NSOutlineView`-backed host in the
/// next iteration for performance on big trees.
struct OutlineTreeView: View {
    let root: FSNode

    var body: some View {
        List {
            OutlineGroup(root, children: \.outlineChildren) { node in
                row(for: node)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func row(for node: FSNode) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ColorPalette.shared.color(for: node.kindID))
                .frame(width: 8, height: 8)
            Image(systemName: icon(for: node))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(node.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(ByteFormatter.format(node.physicalSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private func icon(for node: FSNode) -> String {
        switch node.fileType {
        case .directory:    return "folder"
        case .package:      return "shippingbox"
        case .symlink:      return "arrow.turn.up.right"
        case .mountPoint:   return "externaldrive"
        case .synthetic:    return "circle.dashed"
        case .regularFile:  return "doc"
        }
    }
}

extension FSNode {
    /// `OutlineGroup` interprets `nil` as "leaf" and an empty array as
    /// "empty container". We want leaves to collapse instead of showing
    /// a disclosure triangle, so files return `nil`.
    fileprivate var outlineChildren: [FSNode]? {
        isContainer ? children : nil
    }
}

#Preview {
    let root = FSNode(
        url: URL(fileURLWithPath: "/tmp/example"),
        displayName: "example",
        fileType: .directory,
        depth: 0
    )
    let a = FSNode(
        url: URL(fileURLWithPath: "/tmp/example/a.txt"),
        displayName: "a.txt",
        fileType: .regularFile,
        logicalSize: 1_024,
        physicalSize: 4_096,
        itemCount: 1
    )
    let b = FSNode(
        url: URL(fileURLWithPath: "/tmp/example/sub"),
        displayName: "sub",
        fileType: .directory
    )
    let c = FSNode(
        url: URL(fileURLWithPath: "/tmp/example/sub/c.txt"),
        displayName: "c.txt",
        fileType: .regularFile,
        logicalSize: 65_536,
        physicalSize: 65_536,
        itemCount: 1
    )
    b.appendChild(c)
    root.appendChild(a)
    root.appendChild(b)
    return OutlineTreeView(root: root)
        .frame(width: 480, height: 360)
}
