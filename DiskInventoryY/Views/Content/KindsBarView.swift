import SwiftUI

/// Horizontal strip of pills below the treemap. Tapping a pill toggles
/// `highlightedKind` on the host view, which dims non-matching cells in
/// the treemap.
struct KindsBarView: View {
    let aggregates: [KindAggregate]
    let totalBytes: Int64
    @Binding var highlightedKind: FileKind.ID?
    @Environment(\.kindColors) private var kindColors

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(aggregates) { kind in
                    pill(for: kind)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.thinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(.separator),
            alignment: .top
        )
    }

    @ViewBuilder
    private func pill(for kind: KindAggregate) -> some View {
        let isActive = highlightedKind == kind.id
        Button {
            if highlightedKind == kind.id {
                highlightedKind = nil
            } else {
                highlightedKind = kind.id
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(kindColors.color(for: kind.id))
                    .frame(width: 8, height: 8)
                Text(kind.displayName)
                    .font(.callout)
                Text(ByteFormatter.format(kind.totalPhysical))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if totalBytes > 0 {
                    Text(percent(of: kind))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isActive
                    ? Color.accentColor.opacity(0.18)
                    : Color.gray.opacity(0.10))
            )
            .overlay(
                Capsule().stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("\(kind.fileCount) file\(kind.fileCount == 1 ? "" : "s") · tap to filter the treemap")
    }

    private func percent(of kind: KindAggregate) -> String {
        guard totalBytes > 0 else { return "" }
        let p = Double(kind.totalPhysical) / Double(totalBytes) * 100
        return String(format: "%.1f%%", p)
    }
}
