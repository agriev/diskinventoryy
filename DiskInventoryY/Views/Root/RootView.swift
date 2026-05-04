import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    /// The id seeded by SwiftUI's `WindowGroup(for:)`. When `nil` this
    /// is a landing window; new scans launched here replace this value
    /// instead of spawning a fresh window.
    let initialScanID: ScanID?

    @State private var scanID: ScanID?
    @State private var volumeService = VolumeService()
    @State private var recents = RecentsStore.shared
    @State private var registry = ScanRegistry.shared
    @State private var settings = AppSettings.shared
    @State private var showFolderImporter = false
    @State private var inspectorVisible = false
    @State private var kindsBarVisible = true
    @State private var selectedNode: FSNode?
    @State private var highlightedKind: FileKind.ID?
    @State private var drillStack: [FSNode] = []
    @State private var fullDiskAccess = PermissionsProbe.hasFullDiskAccess()
    @State private var lastRecordedRoot: URL?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    init(scanID: ScanID?) {
        self.initialScanID = scanID
        _scanID = State(initialValue: scanID)
    }

    private var controller: ScanController? {
        guard let scanID else { return nil }
        return registry.controllers[scanID]
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                PermissionsBanner(granted: $fullDiskAccess)
                detail
            }
            .toolbar { toolbar }
        }
        .inspector(isPresented: $inspectorVisible) {
            InspectorPlaceholderView(node: selectedNode)
                .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                fullDiskAccess = PermissionsProbe.hasFullDiskAccess()
            }
        }
        .onChange(of: scanID) { _, _ in
            selectedNode = nil
            highlightedKind = nil
            drillStack = []
            lastRecordedRoot = nil
        }
        .onChange(of: controller?.phase) { _, phase in
            guard let phase else { return }
            if case .done = phase, let result = controller?.result, result.rootURL != lastRecordedRoot {
                let entry = RecentsStore.Entry(
                    url: result.rootURL,
                    displayName: result.rootURL.lastPathComponent.isEmpty
                        ? result.rootURL.path : result.rootURL.lastPathComponent,
                    lastScanned: result.finishedAt,
                    totalBytes: result.totalBytes
                )
                recents.record(entry)
                lastRecordedRoot = result.rootURL
                drillStack = []
                selectedNode = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFolderRequested)) { _ in
            showFolderImporter = true
        }
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                openScan(url: url)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, url.hasDirectoryPath, !urlBelongsToCurrentScan(url) {
                        DispatchQueue.main.async { openScan(url: url) }
                    }
                }
            }
            return true
        }
    }

    /// True if `url` is the currently scanned root or one of its
    /// descendants — i.e. the user is dragging a folder cell from the
    /// treemap onto the same window. We swallow those so the drop
    /// doesn't accidentally start a new scan of the same tree.
    private func urlBelongsToCurrentScan(_ url: URL) -> Bool {
        guard let rootURL = controller?.result?.rootURL else { return false }
        let target = url.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        return target == rootPath || target.hasPrefix(rootPath + "/")
    }

    /// Either run the scan in this window (when it's the empty landing
    /// window) or open a new window for the new scan.
    private func openScan(url: URL) {
        let id = registry.startNewScan(url: url, options: settings.scanOptions)
        if scanID == nil {
            // Empty landing window — adopt the new scan in place.
            selectedNode = nil
            highlightedKind = nil
            drillStack = []
            lastRecordedRoot = nil
            scanID = id
        } else {
            // This window already shows a scan; open a new window.
            openWindow(value: ScanID?.some(id))
        }
    }

    /// Re-scan the currently shown root in the same window.
    private func refreshScan() {
        guard let controller, let url = controller.result?.rootURL ?? controller.rootURL else { return }
        selectedNode = nil
        drillStack = []
        controller.scan(url: url, options: settings.scanOptions)
    }

    /// True if the selected node is a real (non-synthetic) container
    /// that we can re-scan in place.
    private var canRefreshSelection: Bool {
        guard let node = selectedNode, controller != nil else { return false }
        return node.isContainer && !node.isSynthetic
    }

    /// Re-scan only the selected folder. Replaces its children atomically
    /// once the mini-scan finishes; sizes bubble up through the parent
    /// chain via `FSNode.replaceChildren`. The current selection is
    /// cleared because the FSNode references inside the subtree are
    /// thrown away.
    private func refreshSelection() {
        guard let controller, let node = selectedNode, canRefreshSelection else { return }
        selectedNode = nil
        controller.refreshSubtree(node, options: settings.scanOptions)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List {
            DrivesSection(volumes: volumeService.volumes) { url in
                openScan(url: url)
            }
            RecentsSection(
                entries: recents.entries,
                onPick: { url in openScan(url: url) },
                onClear: { recents.clear() }
            )
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let controller {
            scanContent(for: controller)
        } else {
            EmptyStateView { showFolderImporter = true }
        }
    }

    @ViewBuilder
    private func scanContent(for controller: ScanController) -> some View {
        switch controller.phase {
        case .idle:
            EmptyStateView { showFolderImporter = true }
        case .scanning:
            ScanProgressView(progress: controller.progress) {
                controller.cancel()
            }
        case .done:
            if let result = controller.result {
                let displayedRoot = drillStack.last ?? result.root
                ContentSplitView(
                    root: displayedRoot,
                    selectedNode: $selectedNode,
                    highlightedKind: $highlightedKind,
                    kindsBarVisible: kindsBarVisible,
                    drillStack: drillStack,
                    cushionIntensity: settings.cushionIntensity,
                    depthContrast: settings.depthContrast,
                    sizeMetric: settings.sizeMode == .logical ? .logical : .physical,
                    algorithm: settings.treemapAlgorithm,
                    onDrillIn: { node in
                        if node.isContainer {
                            drillStack.append(node)
                            selectedNode = nil
                        }
                    },
                    onDrillUp: { count in
                        let target = max(0, drillStack.count - count)
                        drillStack.removeLast(drillStack.count - target)
                        selectedNode = nil
                    },
                    rootName: result.rootURL.lastPathComponent.isEmpty
                        ? result.rootURL.path
                        : result.rootURL.lastPathComponent
                )
                .navigationTitle(displayedRoot.displayName)
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
            .help("Open a folder or volume to scan (⌘O)")
            .keyboardShortcut("o", modifiers: .command)

            Button {
                refreshScan()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Re-scan the current root (⌘R)")
            .keyboardShortcut("r", modifiers: .command)
            .disabled(controller?.result?.rootURL == nil && controller?.rootURL == nil)

            Button {
                refreshSelection()
            } label: {
                Label("Refresh Selection", systemImage: "arrow.clockwise.circle")
            }
            .help("Re-scan the selected folder (⇧⌘R)")
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!canRefreshSelection)

            Button {
                kindsBarVisible.toggle()
            } label: {
                Label("Kinds", systemImage: "list.bullet.rectangle")
            }
            .help("Show or hide the Kinds bar")

            Button {
                inspectorVisible.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Show or hide the Inspector (⌃⌘I)")
            .keyboardShortcut("i", modifiers: [.command, .control])
        }
    }
}

// MARK: - Sidebar sections

struct DrivesSection: View {
    let volumes: [VolumeInfo]
    var onSelect: (URL) -> Void

    var body: some View {
        Section("Drives") {
            if volumes.isEmpty {
                Label("No volumes mounted", systemImage: "externaldrive")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(volumes, id: \.url) { volume in
                    Button {
                        onSelect(volume.url)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(volume.name).lineLimit(1)
                                if volume.totalCapacity > 0 {
                                    Text("\(ByteFormatter.format(volume.availableForImportant)) free of \(ByteFormatter.format(volume.totalCapacity))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: volume.isRemovable
                                  ? "externaldrive.fill"
                                  : "externaldrive.fill.badge.checkmark")
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Scan \(volume.name) (\(volume.url.path))")
                }
            }
        }
    }
}

struct RecentsSection: View {
    let entries: [RecentsStore.Entry]
    var onPick: (URL) -> Void
    var onClear: () -> Void

    var body: some View {
        Section {
            if entries.isEmpty {
                Label("No recent scans", systemImage: "clock")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    Button {
                        onPick(entry.url)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.displayName).lineLimit(1)
                                Text(ByteFormatter.format(entry.totalBytes))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "clock")
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Re-scan \(entry.url.path)")
                }
            }
        } header: {
            HStack {
                Text("Recent Scans")
                Spacer()
                if !entries.isEmpty {
                    Button("Clear", action: onClear)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Content split

struct ContentSplitView: View {
    let root: FSNode
    @Binding var selectedNode: FSNode?
    @Binding var highlightedKind: FileKind.ID?
    let kindsBarVisible: Bool
    let drillStack: [FSNode]
    let cushionIntensity: Double
    let depthContrast: Double
    let sizeMetric: TreemapLayout.SizeMetric
    let algorithm: TreemapLayout.Algorithm
    var onDrillIn: (FSNode) -> Void
    var onDrillUp: (Int) -> Void
    let rootName: String

    @State private var aggregates: [KindAggregate] = []

    var body: some View {
        VStack(spacing: 0) {
            if !drillStack.isEmpty {
                breadcrumbs
            }
            VSplitView {
                OutlineHost(
                    root: root,
                    selectedNode: $selectedNode
                )
                .frame(minHeight: 160, idealHeight: 280)
                TreemapHost(
                    root: root,
                    selectedNode: $selectedNode,
                    highlightedKind: highlightedKind,
                    cushionIntensity: cushionIntensity,
                    depthContrast: depthContrast,
                    sizeMetric: sizeMetric,
                    algorithm: algorithm,
                    onDrillIn: onDrillIn
                )
                .frame(minHeight: 200, idealHeight: 360)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            if kindsBarVisible {
                KindsBarView(
                    aggregates: aggregates,
                    totalBytes: max(sizeMetric == .logical ? root.logicalSize : root.physicalSize, 1),
                    highlightedKind: $highlightedKind
                )
            }
        }
        .task(id: ObjectIdentifier(root)) {
            aggregates = KindsAggregator.aggregate(root)
        }
    }

    @ViewBuilder
    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            Button(rootName) {
                onDrillUp(drillStack.count)
            }
            .buttonStyle(.link)
            ForEach(Array(drillStack.enumerated()), id: \.offset) { index, node in
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if index == drillStack.count - 1 {
                    Text(node.displayName).bold()
                } else {
                    Button(node.displayName) {
                        onDrillUp(drillStack.count - index - 1)
                    }
                    .buttonStyle(.link)
                }
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(.separator),
            alignment: .bottom
        )
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
            Text("Choose a folder or volume to begin scanning. You can also drop a folder onto this window.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(action: openFolder) {
                Label("Open Folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Choose a folder or volume to scan")
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
    @State private var trashError: String?
    @State private var showTrashConfirm = false

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
                Divider()
                actions
                if let trashError {
                    Text(trashError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .confirmationDialog(
            "Move \(node.displayName) to Trash?",
            isPresented: $showTrashConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { performTrash() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will move the item to the system Trash. The treemap won't update until the next refresh.")
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                FileActions.revealInFinder(node.url)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Show this item in Finder")

            Button {
                FileActions.quickLook(node.url)
            } label: {
                Label("Quick Look", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Preview with Quick Look")

            Button {
                FileActions.openWithDefaultApp(node.url)
            } label: {
                Label("Open with Default App", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!node.isContainer && node.fileType == .directory)
            .help("Open with the system default application")

            Button(role: .destructive) {
                trashError = nil
                showTrashConfirm = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(node.isSynthetic)
            .help("Move this item to the system Trash")
        }
    }

    private func performTrash() {
        do {
            _ = try FileActions.moveToTrash(node.url)
        } catch {
            trashError = "Couldn't move to Trash: \(error.localizedDescription)"
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
    RootView(scanID: nil)
        .frame(width: 1200, height: 800)
}
