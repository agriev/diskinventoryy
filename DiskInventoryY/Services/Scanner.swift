import Foundation

/// Options that govern a single scan. Defaults match the original
/// Disk Inventory X behavior on a developer's machine.
struct ScanOptions: Sendable {
    var includeHidden: Bool = true
    var descendIntoPackages: Bool = false
    var followSymlinks: Bool = false
    var crossVolumeBoundaries: Bool = false
    /// Absolute paths that should never be entered. Used at the
    /// volume root to skip pseudo-filesystems.
    var excludedPaths: Set<String> = ["/dev", "/.vol", "/Volumes/.timemachine"]

    static let `default` = ScanOptions()
}

/// Drives a single scan.
///
/// The scanner is an actor that owns the partial tree, the progress
/// stream, and the worker `Task`. Public methods are async-friendly and
/// safe to call from any isolation domain.
actor DiskScanner {
    // MARK: - State

    enum State: Sendable {
        case idle
        case running(rootURL: URL, root: FSNode)
        case finished(ScanResult)
        case cancelled(partial: FSNode?)
        case failed(any Error)
    }

    private(set) var state: State = .idle
    private let enumerator: any FilesystemEnumerating
    private let kindDetector: KindDetector
    private var workTask: Task<Void, Never>?
    private var continuation: AsyncStream<ScanProgress>.Continuation?
    private var progress: ScanProgress = .zero
    /// 30 Hz throttle for outbound progress events.
    private var lastEmit: ContinuousClock.Instant = .now
    private static let emitInterval: Duration = .milliseconds(33)

    init(
        enumerator: any FilesystemEnumerating = FilesystemEnumeratorFallback(),
        kindDetector: KindDetector = KindDetector()
    ) {
        self.enumerator = enumerator
        self.kindDetector = kindDetector
    }

    // MARK: - Public API

    /// Begin scanning. The returned stream emits progress updates and
    /// completes when the scan finishes, is cancelled, or fails. Call
    /// `result()` afterwards for the final tree.
    func start(at rootURL: URL, options: ScanOptions = .default) -> AsyncStream<ScanProgress> {
        cancel()
        state = .idle
        progress = .zero

        let root = FSNode(
            url: rootURL,
            displayName: rootURL.lastPathComponent.isEmpty ? rootURL.path : rootURL.lastPathComponent,
            fileType: .directory,
            depth: 0
        )
        state = .running(rootURL: rootURL, root: root)

        let stream = AsyncStream<ScanProgress> { cont in
            self.continuation = cont
            cont.onTermination = { [weak self] _ in
                Task { await self?.handleStreamTermination() }
            }
        }

        let started = Date()
        workTask = Task.detached(priority: .userInitiated) { [enumerator] in
            await self.run(root: root, options: options, startedAt: started, enumerator: enumerator)
        }
        return stream
    }

    /// Stop the in-flight scan. Idempotent; the partial tree is kept.
    func cancel() {
        workTask?.cancel()
        workTask = nil
        if case .running(_, let root) = state {
            state = .cancelled(partial: root)
        }
        finishStream(with: .cancelled)
    }

    /// Final result once the scan has finished. Throws if the scan
    /// failed or hasn't been started.
    func result() throws -> ScanResult {
        switch state {
        case .finished(let r): return r
        case .failed(let e):   throw e
        case .cancelled:       throw ScanError.cancelled
        case .idle, .running:  throw ScanError.cancelled
        }
    }

    // MARK: - Worker

    private func run(
        root: FSNode,
        options: ScanOptions,
        startedAt: Date,
        enumerator: any FilesystemEnumerating
    ) async {
        await emit(.scanning, currentURL: root.url, force: true)

        var stack: [FSNode] = [root]
        var totalFiles: Int64 = 0
        var totalDirectories: Int64 = 0
        var totalBytes: Int64 = 0
        let rootVolumeID = (try? root.url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject

        while let parent = stack.popLast() {
            if Task.isCancelled {
                await finalize(root: root,
                               startedAt: startedAt,
                               totalFiles: totalFiles,
                               totalDirectories: totalDirectories,
                               totalBytes: totalBytes,
                               phase: .cancelled)
                return
            }

            await emit(.scanning, currentURL: parent.url)
            await Task.yield()

            let entries: [FSEntry]
            do {
                entries = try enumerator.enumerate(directoryURL: parent.url)
            } catch let error as ScanError {
                await record(error: error, on: parent)
                continue
            } catch {
                await record(error: .io(parent.url, error), on: parent)
                continue
            }

            for entry in entries {
                if shouldSkip(entry: entry, parent: parent, options: options, rootVolumeID: rootVolumeID) {
                    continue
                }

                let node = makeNode(from: entry)
                await attach(node, to: parent)

                switch node.fileType {
                case .directory:
                    totalDirectories &+= 1
                    stack.append(node)
                case .package:
                    totalDirectories &+= 1
                    if options.descendIntoPackages {
                        stack.append(node)
                    }
                default:
                    totalFiles &+= 1
                    totalBytes &+= node.physicalSize
                }
            }

            progress.filesScanned = totalFiles
            progress.directoriesScanned = totalDirectories
            progress.bytesScanned = totalBytes
        }

        await finalize(root: root,
                       startedAt: startedAt,
                       totalFiles: totalFiles,
                       totalDirectories: totalDirectories,
                       totalBytes: totalBytes,
                       phase: .done)
    }

    private func shouldSkip(
        entry: FSEntry,
        parent: FSNode,
        options: ScanOptions,
        rootVolumeID: NSObject?
    ) -> Bool {
        if !options.includeHidden, entry.flags.contains(.hidden) {
            return true
        }
        if entry.flags.contains(.symlink), !options.followSymlinks {
            return true
        }
        if options.excludedPaths.contains(entry.url.path) {
            return true
        }
        if !options.crossVolumeBoundaries,
           let rootVolumeID,
           let entryVolumeID = (try? entry.url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject,
           entryVolumeID != rootVolumeID {
            return true
        }
        return false
    }

    private func makeNode(from entry: FSEntry) -> FSNode {
        let isPackage = entry.fileType == .package
        let isLeaf = entry.fileType != .directory && !isPackage
        let kindID = kindDetector.kind(
            forURL: entry.url,
            fileType: entry.fileType,
            isPackage: isPackage
        )

        var logical = entry.logicalSize
        var physical = entry.physicalSize
        var itemCount: Int32 = isLeaf ? 1 : 0

        // Packages render as leaves but should report their contents'
        // total disk usage. The `descendIntoPackages` toggle, when on,
        // skips this and treats them as regular directories upstream.
        if isPackage {
            let totals = Self.aggregatePackageSize(at: entry.url)
            logical = max(logical, totals.logical)
            physical = max(physical, totals.physical)
            itemCount = totals.count
        }

        return FSNode(
            url: entry.url,
            displayName: entry.name,
            kind: .regular,
            fileType: entry.fileType,
            logicalSize: logical,
            physicalSize: physical,
            itemCount: itemCount,
            kindID: kindID,
            isPackage: isPackage,
            isMountPoint: false,
            mtime: entry.mtime,
            flags: entry.flags
        )
    }

    /// If `url` is the root of a mounted volume, returns its
    /// `VolumeInfo`. Used to attach synthetic Free/Other space
    /// siblings only on volume scans, not folder scans.
    private nonisolated func volumeInfoIfRoot(_ url: URL) -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [
            .volumeURLKey, .volumeNameKey, .volumeLocalizedNameKey,
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsReadOnlyKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        guard let volumeURL = values.volume,
              volumeURL.standardizedFileURL == url.standardizedFileURL else {
            return nil
        }
        let name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
        return VolumeInfo(
            name: name,
            url: url,
            fileSystemType: nil,
            totalCapacity: Int64(values.volumeTotalCapacity ?? 0),
            availableCapacity: Int64(values.volumeAvailableCapacity ?? 0),
            availableForImportant: Int64(values.volumeAvailableCapacityForImportantUsage ?? 0),
            isRemovable: values.volumeIsRemovable ?? false,
            isLocal: values.volumeIsLocal ?? true,
            isReadOnly: values.volumeIsReadOnly ?? false
        )
    }

    /// Append synthetic Free Space / Other Space siblings under `root`
    /// so the treemap reflects how much of the volume isn't covered by
    /// what we walked: TCC-protected paths, snapshots, purgeable, etc.
    private func attachVolumeSpaceSiblings(to root: FSNode, volume: VolumeInfo) {
        guard volume.totalCapacity > 0 else { return }
        let scanned = root.physicalSize
        let free = max(0, volume.availableForImportant)
        let other = max(0, volume.totalCapacity - scanned - free)

        if free > 0 {
            let freeNode = FSNode(
                url: URL(string: "diy-virtual://\(volume.url.path)/free")!,
                displayName: "Free space",
                kind: .freeSpace,
                fileType: .synthetic,
                logicalSize: free,
                physicalSize: free,
                itemCount: 0,
                kindID: FileKind.freeSpace.id,
                isPackage: false,
                isMountPoint: false,
                depth: 0,
                mtime: nil,
                flags: []
            )
            root.appendChild(freeNode)
        }
        if other > 0 {
            let otherNode = FSNode(
                url: URL(string: "diy-virtual://\(volume.url.path)/other")!,
                displayName: "Other space",
                kind: .otherSpace,
                fileType: .synthetic,
                logicalSize: other,
                physicalSize: other,
                itemCount: 0,
                kindID: FileKind.otherSpace.id,
                isPackage: false,
                isMountPoint: false,
                depth: 0,
                mtime: nil,
                flags: []
            )
            root.appendChild(otherNode)
        }
    }

    /// Sum file sizes inside a package without exposing the children
    /// in the tree. Uses `FileManager.enumerator`; acceptable for the
    /// single-package case (.app, .xcodeproj, etc.).
    private static func aggregatePackageSize(at url: URL) -> (logical: Int64, physical: Int64, count: Int32) {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey, .totalFileAllocatedSizeKey, .isRegularFileKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0, 0)
        }
        var logical: Int64 = 0
        var physical: Int64 = 0
        var count: Int32 = 0
        for case let entry as URL in enumerator {
            guard let values = try? entry.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            logical &+= Int64(values.fileSize ?? 0)
            physical &+= Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            count &+= 1
        }
        return (logical, physical, count)
    }

    private func attach(_ node: FSNode, to parent: FSNode) async {
        parent.appendChild(node)
    }

    private func record(error: ScanError, on parent: FSNode) async {
        var existing = parent.errors ?? []
        existing.append(error)
        parent.errors = existing
        if case .noAccess = error {
            parent.flags.insert(.accessDenied)
        }
    }

    private func finalize(
        root: FSNode,
        startedAt: Date,
        totalFiles: Int64,
        totalDirectories: Int64,
        totalBytes: Int64,
        phase: ScanProgress.Phase
    ) async {
        let finishedAt = Date()
        let volumeInfo = volumeInfoIfRoot(root.url)
        if phase == .done, let volume = volumeInfo {
            attachVolumeSpaceSiblings(to: root, volume: volume)
        }
        let result = ScanResult(
            id: ScanID(),
            rootURL: root.url,
            root: root,
            volume: volumeInfo,
            startedAt: startedAt,
            finishedAt: finishedAt,
            phase: phase,
            totalFiles: totalFiles,
            totalDirectories: totalDirectories,
            totalBytes: totalBytes
        )
        switch phase {
        case .done:
            state = .finished(result)
        case .cancelled:
            state = .cancelled(partial: root)
        default:
            break
        }
        await emit(phase, currentURL: nil, force: true)
        finishStream(with: phase)
    }

    // MARK: - Progress

    private func emit(_ phase: ScanProgress.Phase, currentURL: URL?, force: Bool = false) async {
        progress.phase = phase
        progress.currentURL = currentURL
        let now = ContinuousClock.now
        if !force && now - lastEmit < Self.emitInterval { return }
        lastEmit = now
        continuation?.yield(progress)
    }

    private func finishStream(with phase: ScanProgress.Phase) {
        progress.phase = phase
        continuation?.yield(progress)
        continuation?.finish()
        continuation = nil
    }

    private func handleStreamTermination() {
        // Consumer dropped the stream — do nothing extra; the worker
        // task continues so `result()` can still be queried later.
    }
}
