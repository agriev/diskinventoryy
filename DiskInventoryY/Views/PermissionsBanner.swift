import SwiftUI

/// Sits at the top of the window when Full Disk Access is missing.
/// Self-dismisses on the next `granted` re-probe.
struct PermissionsBanner: View {
    @Binding var granted: Bool

    var body: some View {
        if granted { EmptyView() } else { content }
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access not granted")
                    .font(.subheadline.bold())
                Text("Without it, scans of protected paths (Mail, Messages, system Library, …) will be incomplete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Open Settings") {
                PermissionsProbe.openSystemSettings()
            }
            .controlSize(.small)
            Button {
                granted = PermissionsProbe.hasFullDiskAccess()
            } label: {
                Label("Re-check", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.yellow.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(.separator),
            alignment: .bottom
        )
    }
}
