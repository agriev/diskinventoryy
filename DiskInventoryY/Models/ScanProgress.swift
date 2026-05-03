import Foundation

/// Throttled progress update emitted by `Scanner` while it's working.
/// Counts are running totals, not deltas.
struct ScanProgress: Sendable, Hashable {
    enum Phase: String, Sendable, Hashable {
        case preparing
        case scanning
        case finalizing
        case done
        case cancelled
    }

    var phase: Phase
    var filesScanned: Int64
    var directoriesScanned: Int64
    var bytesScanned: Int64
    var currentURL: URL?

    static let zero = ScanProgress(
        phase: .preparing,
        filesScanned: 0,
        directoriesScanned: 0,
        bytesScanned: 0,
        currentURL: nil
    )
}
