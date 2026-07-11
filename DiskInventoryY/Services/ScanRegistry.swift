import Foundation
import Observation

/// Owns one `ScanController` per `ScanID`. The shared instance lives
/// for the lifetime of the app; each window pulls "its" controller out
/// by id so SwiftUI scene restoration can re-open the same scan in a
/// fresh window.
@MainActor
@Observable
final class ScanRegistry {
    static let shared = ScanRegistry()

    private(set) var controllers: [ScanID: ScanController] = [:]

    /// Returns an existing controller for `id`, or creates a fresh one.
    func controller(for id: ScanID) -> ScanController {
        if let existing = controllers[id] { return existing }
        let new = ScanController()
        controllers[id] = new
        return new
    }

    /// Generate a fresh id, register a new controller, and start the
    /// scan against `url`. Returns the id so the caller can open a
    /// window pointing at it.
    @discardableResult
    func startNewScan(url: URL, options: ScanOptions = .default) -> ScanID {
        let id = ScanID()
        let controller = ScanController()
        controllers[id] = controller
        controller.scan(url: url, options: options)
        return id
    }

    /// Register a freshly-loaded scan (e.g. from a `.dscan` file) as a
    /// new entry. Returns the new id so the caller can open a window
    /// pointing at it.
    @discardableResult
    func adopt(result: ScanResult) -> ScanID {
        let id = ScanID()
        let controller = ScanController()
        controller.adopt(result: result)
        controllers[id] = controller
        return id
    }

    /// Register an idle controller for a brand-new empty window
    /// (File → New Window). The window shows the empty state until the
    /// user picks something to scan.
    func newEmptyID() -> ScanID {
        let id = ScanID()
        controllers[id] = ScanController()
        return id
    }

    /// Cancel the scan and drop the controller. Called when its window
    /// closes.
    func discard(_ id: ScanID) {
        controllers[id]?.cancel()
        controllers.removeValue(forKey: id)
    }
}
