import SwiftUI

struct ScanProgressView: View {
    let progress: ScanProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)

            VStack(spacing: 4) {
                Text("Scanning…")
                    .font(.title2)
                if let url = progress.currentURL {
                    Text(url.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 480)
                }
            }

            HStack(spacing: 24) {
                stat(label: "Files", value: progress.filesScanned.formatted())
                stat(label: "Folders", value: progress.directoriesScanned.formatted())
                stat(label: "Size", value: ByteFormatter.format(progress.bytesScanned))
            }

            Button(role: .cancel, action: onCancel) {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .help("Stop the in-progress scan; the partial tree is kept")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func stat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ScanProgressView(
        progress: ScanProgress(
            phase: .scanning,
            filesScanned: 12_345,
            directoriesScanned: 678,
            bytesScanned: 9_876_543_210,
            currentURL: URL(fileURLWithPath: "/Users/example/very/deep/long/path/file.bin")
        ),
        onCancel: {}
    )
    .frame(width: 600, height: 400)
}
