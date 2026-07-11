import Foundation
import Observation

/// MainActor-bound observable that drives the UI: it owns one
/// `DiskScanner`, marshals its stream onto the main thread, and exposes
/// the current `ScanProgress` / `ScanResult` for views to read.
@MainActor
@Observable
final class ScanController {
    enum Phase: Equatable {
        case idle
        case scanning
        case done
        case cancelled
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: ScanProgress = .zero
    private(set) var result: ScanResult?

    /// URL of the most recently requested scan; useful for error messages.
    private(set) var rootURL: URL?

    private let scanner = DiskScanner()
    private var driveTask: Task<Void, Never>?

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    func scan(url: URL, options: ScanOptions = .default) {
        // Only cancel the local drive task here. scanner.start() cancels
        // the previous worker itself, on the actor, in order — firing an
        // unstructured `Task { scanner.cancel() }` from here could land
        // AFTER the new start() and kill the fresh scan.
        driveTask?.cancel()
        rootURL = url
        progress = .zero
        result = nil
        phase = .scanning

        driveTask = Task { [weak self] in
            await self?.drive(url: url, options: options)
        }
    }

    func cancel() {
        driveTask?.cancel()
        driveTask = nil
        Task { [scanner] in await scanner.cancel() }
    }

    /// Replace the current state with a pre-existing `ScanResult` —
    /// used when opening a saved `.dscan` file. No work is dispatched
    /// to the scanner.
    func adopt(result: ScanResult) {
        cancel()
        rootURL = result.rootURL
        self.result = result
        progress = ScanProgress(
            phase: .done,
            filesScanned: result.totalFiles,
            directoriesScanned: result.totalDirectories,
            bytesScanned: result.totalBytes,
            currentURL: nil
        )
        phase = .done
    }

    /// Re-scan a single subtree. Replaces `node`'s children with a
    /// freshly-walked tree; sizes propagate upward through the
    /// existing `replaceChildren` delta logic. Selection that was
    /// inside the subtree should be cleared by the caller — the
    /// subtree's old `FSNode` references go away.
    func refreshSubtree(_ node: FSNode, options: ScanOptions = .default) {
        Task { [weak self] in
            await self?.runRefresh(of: node, options: options)
        }
    }

    private func runRefresh(of node: FSNode, options: ScanOptions) async {
        let oneShot = DiskScanner()
        let stream = await oneShot.start(at: node.url, options: options)
        for await update in stream {
            if update.phase == .done || update.phase == .cancelled { break }
        }
        do {
            let scanResult = try await oneShot.result()
            let fresh = scanResult.root
            node.replaceChildren(fresh.children)
            node.physicalSize = fresh.physicalSize
            node.logicalSize = fresh.logicalSize
            node.itemCount = fresh.itemCount
            node.mtime = fresh.mtime
        } catch {
            // Keep the old subtree; the caller can retry.
        }
    }

    private func drive(url: URL, options: ScanOptions) async {
        let stream = await scanner.start(at: url, options: options)
        var lastPhase: ScanProgress.Phase = .preparing
        for await update in stream {
            if Task.isCancelled { break }
            self.progress = update
            lastPhase = update.phase
            if update.phase == .done || update.phase == .cancelled {
                break
            }
        }

        // A superseded drive (scan() started a newer one and cancelled
        // us) wakes up here with a nil-terminated stream. It must not
        // touch `phase` — that would stomp the new scan's state.
        if Task.isCancelled { return }

        switch lastPhase {
        case .done:
            do {
                let scanResult = try await scanner.result()
                self.result = scanResult
                self.phase = .done
            } catch {
                self.phase = .failed("\(error)")
            }
        case .cancelled:
            self.phase = .cancelled
        default:
            self.phase = .failed("Scan ended unexpectedly")
        }
    }
}
