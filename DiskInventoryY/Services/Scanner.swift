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
    private var workTask: Task<Void, Never>?
    private var continuation: AsyncStream<ScanProgress>.Continuation?
    private var progress: ScanProgress = .zero
    /// 30 Hz throttle for outbound progress events.
    private var lastEmit: ContinuousClock.Instant = .now
    private static let emitInterval: Duration = .milliseconds(33)

    init(enumerator: any FilesystemEnumerating = FilesystemEnumeratorFallback()) {
        self.enumerator = enumerator
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
        let isLeaf = entry.fileType != .directory && entry.fileType != .package
        return FSNode(
            url: entry.url,
            displayName: entry.name,
            kind: .regular,
            fileType: entry.fileType,
            logicalSize: entry.logicalSize,
            physicalSize: entry.physicalSize,
            itemCount: isLeaf ? 1 : 0,
            kindID: FileKind.other.id,
            isPackage: entry.fileType == .package,
            isMountPoint: false,
            mtime: entry.mtime,
            flags: entry.flags
        )
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
        let result = ScanResult(
            id: ScanID(),
            rootURL: root.url,
            root: root,
            volume: nil,
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
