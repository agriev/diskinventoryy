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
        cancel()
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

    private func drive(url: URL, options: ScanOptions) async {
        let stream = await scanner.start(at: url, options: options)
        var lastPhase: ScanProgress.Phase = .preparing
        for await update in stream {
            self.progress = update
            lastPhase = update.phase
            if update.phase == .done || update.phase == .cancelled {
                break
            }
        }

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
