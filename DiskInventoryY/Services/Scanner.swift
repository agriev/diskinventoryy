import Foundation
import os

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

/// State shared between parallel walk workers. Every mutable field is
/// behind an unfair lock; workers touch them at directory granularity
/// (not per file), so contention is negligible.
private final class ScanShared: @unchecked Sendable {
    let enumerator: any FilesystemEnumerating
    let fallback: any FilesystemEnumerating
    let kindDetector: KindDetector
    let options: ScanOptions
    /// `st_dev` of the scan root — compared against each entry's
    /// device id (free from getattrlistbulk) to stop at volume
    /// boundaries without a Foundation syscall per entry.
    let rootDevice: UInt64?
    /// Foundation-level volume id, used only for entries produced by
    /// the fallback enumerator (which doesn't fill `device`).
    let rootVolumeID: NSObject?

    let seenInodes = OSAllocatedUnfairLock<Set<UInt64>>(initialState: [])
    /// Inodes of every directory we've already descended into.
    /// Mountpoints make cycles REAL on APFS: inside the Data volume,
    /// `System/Volumes/Data` is the volume's own mountpoint — same
    /// st_dev, so a device check sails right through and the walk
    /// recurses into itself forever. A visited set stops any cycle.
    let visitedDirs = OSAllocatedUnfairLock<Set<UInt64>>(initialState: [])
    /// files, directories, bytes — running totals for progress.
    let counters = OSAllocatedUnfairLock<(Int64, Int64, Int64)>(initialState: (0, 0, 0))
    let currentURL = OSAllocatedUnfairLock<URL?>(initialState: nil)
    /// Cooperative cancellation for GCD workers — they run outside any
    /// Task context, so `Task.isCancelled` is meaningless there.
    let cancelled = OSAllocatedUnfairLock<Bool>(initialState: false)
    /// Extension → is-package cache so bundle detection costs one
    /// UTType lookup per distinct extension instead of a Foundation
    /// resourceValues call per directory.
    let packageExtensions = OSAllocatedUnfairLock<[String: Bool]>(initialState: [:])

    init(
        enumerator: any FilesystemEnumerating,
        fallback: any FilesystemEnumerating,
        kindDetector: KindDetector,
        options: ScanOptions,
        rootURL: URL
    ) {
        self.enumerator = enumerator
        self.fallback = fallback
        self.kindDetector = kindDetector
        self.options = options

        var st = stat()
        let statOK = stat(rootURL.path, &st) == 0
        self.rootDevice = statOK ? UInt64(UInt32(bitPattern: st.st_dev)) : nil
        self.rootVolumeID = (try? rootURL.resourceValues(forKeys: [.volumeIdentifierKey]))?
            .volumeIdentifier as? NSObject

        if statOK {
            // Seed the visited set with the root itself so a cycle
            // leading straight back (the volume's own mountpoint) is
            // caught on first sight, not after one duplicate level.
            visitedDirs.withLock { _ = $0.insert(st.st_ino) }
        }
    }
}

/// Drives a single scan.
///
/// The traversal is parallel: a shallow serial expansion collects a
/// frontier of independent subdirectories, then a `TaskGroup` builds
/// each subtree concurrently. Every subtree is mutated exclusively by
/// its own task (size propagation stops at the subtree root), so no
/// FSNode is ever written from two threads.
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
    private let fallbackEnumerator: any FilesystemEnumerating
    private let kindDetector: KindDetector
    private var workTask: Task<Void, Never>?
    private var continuation: AsyncStream<ScanProgress>.Continuation?
    private var progress: ScanProgress = .zero

    init(
        enumerator: any FilesystemEnumerating = FilesystemEnumeratorBulk(),
        fallback: any FilesystemEnumerating = FilesystemEnumeratorFallback(),
        kindDetector: KindDetector = KindDetector()
    ) {
        self.enumerator = enumerator
        self.fallbackEnumerator = fallback
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

        let shared = ScanShared(
            enumerator: enumerator,
            fallback: fallbackEnumerator,
            kindDetector: kindDetector,
            options: options,
            rootURL: rootURL
        )

        let started = Date()
        workTask = Task.detached(priority: .userInitiated) {
            await self.run(root: root, shared: shared, startedAt: started)
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

    private func run(root: FSNode, shared: ScanShared, startedAt: Date) async {
        emitNow(.scanning, currentURL: root.url)

        // Phase 1 — shallow serial expansion. Enumerate the first few
        // levels inline until we have enough independent directories
        // to saturate the cores. Files found here are attached
        // directly (serial, safe).
        // A wide frontier matters more than a shallow one: with only
        // ~cores subtrees, one dominant directory (a Chromium checkout,
        // a Photos library) leaves its whole tail on a single worker.
        // 8× cores over up to 4 levels spreads the skew.
        var frontier: [FSNode] = [root]
        let targetWidth = max(32, ProcessInfo.processInfo.activeProcessorCount * 8)
        var expansions = 0
        while !frontier.isEmpty, frontier.count < targetWidth, expansions < 4 {
            if Task.isCancelled { break }
            var next: [FSNode] = []
            for dir in frontier {
                let subdirs = Self.expandOneLevel(of: dir, shared: shared)
                next.append(contentsOf: subdirs)
            }
            frontier = next
            expansions += 1
        }

        // Phase 2 — parallel subtree builds. Each frontier directory
        // is owned exclusively by one worker; totals accumulate inside
        // the subtree and never cross its root, so there is no shared
        // mutation.
        //
        // The workers are pure blocking syscall loops — they MUST NOT
        // run on the Swift Concurrency cooperative pool, or they
        // starve every actor in the process (including this one and
        // the progress ticker). GCD's concurrentPerform sizes itself
        // to the active cores and keeps the cooperative pool free.
        if !Task.isCancelled, !frontier.isEmpty {
            let ticker = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.emitCounters(shared)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            let work = frontier
            await withTaskCancellationHandler {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        DispatchQueue.concurrentPerform(iterations: work.count) { index in
                            Self.buildSubtree(into: work[index], shared: shared)
                        }
                        cont.resume()
                    }
                }
            } onCancel: {
                shared.cancelled.withLock { $0 = true }
            }
            ticker.cancel()
        }

        // Phase 3 — fold the workers' subtree totals into the shallow
        // region (root and the few directories above the frontier).
        // Their counters only saw shallow files during phase 1.
        let frontierIDs = Set(frontier.map(ObjectIdentifier.init))
        Self.recomputeAggregates(root, stopAt: frontierIDs)

        let (files, dirs, bytes) = shared.counters.withLock { $0 }
        let wasCancelled = Task.isCancelled || shared.cancelled.withLock { $0 }
        await finalize(
            root: root,
            startedAt: startedAt,
            totalFiles: files,
            totalDirectories: dirs,
            totalBytes: bytes,
            phase: wasCancelled ? .cancelled : .done
        )
    }

    /// Enumerate exactly one directory, attach its children (serial
    /// context), and return the subdirectories that still need their
    /// own expansion.
    private static func expandOneLevel(of dir: FSNode, shared: ScanShared) -> [FSNode] {
        shared.currentURL.withLock { $0 = dir.url }
        let entries = enumerate(dir.url, shared: shared, recordOn: dir)
        var children: [FSNode] = []
        var subdirs: [FSNode] = []
        var localFiles: Int64 = 0
        var localDirs: Int64 = 0
        var localBytes: Int64 = 0

        for var entry in entries {
            guard !shouldSkip(entry: entry, shared: shared) else { continue }
            dedupeHardlink(&entry, shared: shared)
            promotePackageIfNeeded(&entry, shared: shared)

            let node = makeNode(from: entry, shared: shared)
            children.append(node)

            switch node.fileType {
            case .directory, .package:
                localDirs &+= 1
                if markDirVisited(entry, shared: shared) {
                    subdirs.append(node)
                } else {
                    node.isMountPoint = true   // cycle — don't descend
                }
            default:
                if !node.flags.contains(.hardlinkDuplicate) { localFiles &+= 1 }
                localBytes &+= node.physicalSize
            }
        }

        dir.appendChildren(children)
        shared.counters.withLock {
            $0.0 &+= localFiles; $0.1 &+= localDirs; $0.2 &+= localBytes
        }
        return subdirs
    }

    /// Recursively build the subtree beneath `dir`. Runs synchronously
    /// on a GCD worker thread; mutates only nodes it created (plus
    /// `dir`'s own children array and totals — `dir` is owned by this
    /// worker).
    private static func buildSubtree(into dir: FSNode, shared: ScanShared) {
        if shared.cancelled.withLock({ $0 }) { return }
        shared.currentURL.withLock { $0 = dir.url }

        let entries = enumerate(dir.url, shared: shared, recordOn: dir)
        var children: [FSNode] = []
        children.reserveCapacity(entries.count)
        var localFiles: Int64 = 0
        var localDirs: Int64 = 0
        var localBytes: Int64 = 0

        for var entry in entries {
            guard !shouldSkip(entry: entry, shared: shared) else { continue }
            dedupeHardlink(&entry, shared: shared)
            promotePackageIfNeeded(&entry, shared: shared)

            let node = makeNode(from: entry, shared: shared)

            switch node.fileType {
            case .directory:
                localDirs &+= 1
                if markDirVisited(entry, shared: shared) {
                    buildSubtree(into: node, shared: shared)
                } else {
                    node.isMountPoint = true   // cycle — don't descend
                }
            case .package:
                localDirs &+= 1
                // Size packages by walking their contents at bulk
                // speed. Unless the user opted in, the internals stay
                // hidden: totals are kept, children dropped.
                if markDirVisited(entry, shared: shared) {
                    buildSubtree(into: node, shared: shared)
                    if !shared.options.descendIntoPackages {
                        node.setChildrenPreservingTotals([])
                    }
                } else {
                    node.isMountPoint = true
                }
            default:
                if !node.flags.contains(.hardlinkDuplicate) { localFiles &+= 1 }
                localBytes &+= node.physicalSize
            }
            children.append(node)
        }

        // Single linkage + aggregation pass: children keep the totals
        // their own recursion computed; `dir` sums them once.
        dir.setChildrenPreservingTotals(children)
        var logical: Int64 = 0
        var physical: Int64 = 0
        var items: Int32 = 0
        for child in children {
            logical &+= child.logicalSize
            physical &+= child.physicalSize
            items &+= child.itemCount
        }
        dir.logicalSize = logical
        dir.physicalSize = physical
        dir.itemCount = items

        shared.counters.withLock {
            $0.0 &+= localFiles; $0.1 &+= localDirs; $0.2 &+= localBytes
        }
    }

    /// Recompute aggregate totals for the shallow region (everything
    /// above the parallel frontier). Frontier subtrees carry exact
    /// totals from their workers; this folds them upward. Overwrites,
    /// never adds — safe to run over partially-propagated state.
    @discardableResult
    private static func recomputeAggregates(
        _ node: FSNode,
        stopAt frontier: Set<ObjectIdentifier>
    ) -> (logical: Int64, physical: Int64, items: Int32) {
        if frontier.contains(ObjectIdentifier(node)) || node.children.isEmpty {
            return (node.logicalSize, node.physicalSize, node.itemCount)
        }
        var logical: Int64 = 0
        var physical: Int64 = 0
        var items: Int32 = 0
        for child in node.children {
            let t = recomputeAggregates(child, stopAt: frontier)
            logical &+= t.logical
            physical &+= t.physical
            items &+= t.items
        }
        if node.isContainer {
            node.logicalSize = logical
            node.physicalSize = physical
            node.itemCount = items
        }
        return (node.logicalSize, node.physicalSize, node.itemCount)
    }

    // MARK: - Entry helpers (shared by serial + parallel paths)

    private static func enumerate(
        _ url: URL,
        shared: ScanShared,
        recordOn node: FSNode
    ) -> [FSEntry] {
        do {
            return try shared.enumerator.enumerate(directoryURL: url)
        } catch let error as ScanError {
            if case .noAccess = error {
                record(error: error, on: node)
                return []
            }
            // Bulk enumerator can choke on pseudo-fs; fall back.
        } catch { /* fall through to fallback */ }

        do {
            return try shared.fallback.enumerate(directoryURL: url)
        } catch let error as ScanError {
            record(error: error, on: node)
            return []
        } catch {
            record(error: .io(url, error), on: node)
            return []
        }
    }

    private static func shouldSkip(entry: FSEntry, shared: ScanShared) -> Bool {
        let options = shared.options
        if !options.includeHidden, entry.flags.contains(.hidden) {
            return true
        }
        if entry.flags.contains(.symlink), !options.followSymlinks {
            return true
        }
        if options.excludedPaths.contains(entry.url.path) {
            return true
        }
        if !options.crossVolumeBoundaries {
            // Prefer the device id that came free with the bulk
            // syscall; only entries from the Foundation fallback pay
            // for a resourceValues lookup.
            if let device = entry.device, let rootDevice = shared.rootDevice {
                if device != rootDevice { return true }
            } else if entry.fileType == .directory,
                      let rootVolumeID = shared.rootVolumeID,
                      let entryVolumeID = (try? entry.url.resourceValues(forKeys: [.volumeIdentifierKey]))?
                          .volumeIdentifier as? NSObject,
                      entryVolumeID != rootVolumeID {
                return true
            }
        }
        return false
    }

    /// Returns true if this directory hasn't been visited yet (and
    /// marks it). False means a cycle — e.g. a volume's own mountpoint
    /// reachable from inside the volume — and the caller must not
    /// descend. Directories without an inode (fallback enumerator)
    /// are always walked; Foundation's enumerator doesn't loop.
    private static func markDirVisited(_ entry: FSEntry, shared: ScanShared) -> Bool {
        guard let inode = entry.inode else { return true }
        return shared.visitedDirs.withLock { $0.insert(inode).inserted }
    }

    private static func dedupeHardlink(_ entry: inout FSEntry, shared: ScanShared) {
        guard entry.fileType == .regularFile, let inode = entry.inode else { return }
        let inserted = shared.seenInodes.withLock { $0.insert(inode).inserted }
        if !inserted {
            entry.flags.insert(.hardlinkDuplicate)
            entry.physicalSize = 0
            entry.logicalSize = 0
        }
    }

    /// Bundle detection without a Foundation syscall per directory: a
    /// package must have a path extension, and package-ness is a pure
    /// function of that extension — cache it.
    private static func promotePackageIfNeeded(_ entry: inout FSEntry, shared: ScanShared) {
        guard entry.fileType == .directory else { return }
        let ext = entry.url.pathExtension
        guard !ext.isEmpty else { return }
        let lowered = ext.lowercased()

        let cached = shared.packageExtensions.withLock { $0[lowered] }
        let isPackage: Bool
        if let cached {
            isPackage = cached
        } else {
            isPackage = (try? entry.url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
            shared.packageExtensions.withLock { $0[lowered] = isPackage }
        }
        if isPackage {
            entry.fileType = .package
        }
    }

    private static func makeNode(from entry: FSEntry, shared: ScanShared) -> FSNode {
        let isPackage = entry.fileType == .package
        let isLeaf = entry.fileType != .directory && !isPackage
        let kindID = shared.kindDetector.kind(
            forURL: entry.url,
            fileType: entry.fileType,
            isPackage: isPackage
        )
        return FSNode(
            url: entry.url,
            displayName: entry.name,
            kind: .regular,
            fileType: entry.fileType,
            logicalSize: entry.logicalSize,
            physicalSize: entry.physicalSize,
            itemCount: isLeaf ? 1 : 0,
            kindID: kindID,
            isPackage: isPackage,
            isMountPoint: false,
            mtime: entry.mtime,
            flags: entry.flags
        )
    }

    private static func record(error: ScanError, on node: FSNode) {
        var existing = node.errors ?? []
        existing.append(error)
        node.errors = existing
        if case .noAccess = error {
            node.flags.insert(.accessDenied)
        }
    }

    // MARK: - Volume info / synthetic siblings

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
        finishStream(with: phase)
    }

    // MARK: - Progress

    /// Pulled by a 10 Hz ticker while workers run; workers themselves
    /// never suspend to report progress.
    private func emitCounters(_ shared: ScanShared) {
        let (files, dirs, bytes) = shared.counters.withLock { $0 }
        progress.phase = .scanning
        progress.filesScanned = files
        progress.directoriesScanned = dirs
        progress.bytesScanned = bytes
        progress.currentURL = shared.currentURL.withLock { $0 }
        continuation?.yield(progress)
    }

    private func emitNow(_ phase: ScanProgress.Phase, currentURL: URL?) {
        progress.phase = phase
        progress.currentURL = currentURL
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
