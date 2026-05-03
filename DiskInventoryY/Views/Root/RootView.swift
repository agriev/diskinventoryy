import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @State private var controller = ScanController()
    @State private var showFolderImporter = false
    @State private var inspectorVisible = false
    @State private var selectedNode: FSNode?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .toolbar { toolbar }
        }
        .inspector(isPresented: $inspectorVisible) {
            InspectorPlaceholderView(node: selectedNode)
                .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
        }
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                selectedNode = nil
                controller.scan(url: url)
            }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List {
            Section("Drives") {
                Label("No volumes yet", systemImage: "externaldrive")
                    .foregroundStyle(.secondary)
            }
            Section("Recent Scans") {
                Label("No recent scans", systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch controller.phase {
        case .idle:
            EmptyStateView { showFolderImporter = true }
        case .scanning:
            ScanProgressView(progress: controller.progress) {
                controller.cancel()
            }
        case .done:
            if let result = controller.result {
                ContentSplitView(
                    root: result.root,
                    selectedNode: $selectedNode
                )
                .navigationTitle(result.rootURL.lastPathComponent.isEmpty
                                 ? result.rootURL.path
                                 : result.rootURL.lastPathComponent)
                .navigationSubtitle(summary(for: result))
            } else {
                EmptyStateView { showFolderImporter = true }
            }
        case .cancelled:
            ScanCancelledView(rootURL: controller.rootURL) {
                showFolderImporter = true
            }
        case .failed(let message):
            ScanFailedView(message: message) {
                showFolderImporter = true
            }
        }
    }

    private func summary(for result: ScanResult) -> String {
        let files = result.totalFiles.formatted()
        let folders = result.totalDirectories.formatted()
        let size = ByteFormatter.format(result.totalBytes)
        return "\(files) files · \(folders) folders · \(size)"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showFolderImporter = true
            } label: {
                Label("Open Folder", systemImage: "folder.badge.plus")
            }
            .help("Choose a folder or volume to scan")
            .keyboardShortcut("o", modifiers: .command)

            Button {
                inspectorVisible.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle inspector")
            .keyboardShortcut("i", modifiers: [.command, .control])
        }
    }
}

// MARK: - Content split

struct ContentSplitView: View {
    let root: FSNode
    @Binding var selectedNode: FSNode?

    var body: some View {
        VSplitView {
            OutlineTreeView(root: root, selectedNode: $selectedNode)
                .frame(minHeight: 160, idealHeight: 280)
            TreemapHost(root: root, selectedNode: $selectedNode)
                .frame(minHeight: 200, idealHeight: 360)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

// MARK: - State views

struct EmptyStateView: View {
    var openFolder: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
            Text("No scan yet")
                .font(.title2)
            Text("Choose a folder or volume to begin scanning.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(action: openFolder) {
                Label("Open Folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanCancelledView: View {
    let rootURL: URL?
    var openFolder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.octagon")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Scan cancelled")
                .font(.title3)
            if let rootURL {
                Text(rootURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Button("Open Another Folder", action: openFolder)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanFailedView: View {
    let message: String
    var openFolder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.orange)
            Text("Scan failed")
                .font(.title3)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button("Try Again", action: openFolder)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InspectorPlaceholderView: View {
    let node: FSNode?

    var body: some View {
        if let node {
            InspectorContent(node: node)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Select an item to inspect")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

private struct InspectorContent: View {
    let node: FSNode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(ColorPalette.shared.color(for: node.kindID))
                        .frame(width: 12, height: 12)
                    Text(node.displayName)
                        .font(.title3)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Text(node.url.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Divider()
                row("Physical size", value: ByteFormatter.format(node.physicalSize))
                row("Logical size", value: ByteFormatter.format(node.logicalSize))
                row("Items", value: node.itemCount.formatted())
                row("Kind", value: node.kindID.capitalized)
                if let mtime = node.mtime {
                    row("Modified", value: mtime.formatted(.dateTime.year().month().day().hour().minute()))
                }
                if !node.flags.isEmpty {
                    row("Flags", value: flagsDescription)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    private var flagsDescription: String {
        var labels: [String] = []
        if node.flags.contains(.symlink) { labels.append("symlink") }
        if node.flags.contains(.hidden) { labels.append("hidden") }
        if node.flags.contains(.firmlinkTarget) { labels.append("firmlink target") }
        if node.flags.contains(.hardlinkDuplicate) { labels.append("hardlink duplicate") }
        if node.flags.contains(.accessDenied) { labels.append("no access") }
        return labels.joined(separator: ", ")
    }
}

#Preview {
    RootView()
        .frame(width: 1100, height: 700)
}
