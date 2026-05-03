import Foundation

/// The output of a completed (or cancelled) scan. The root node owns the
/// whole tree; volume info is captured at scan start so the synthetic
/// *Other* and *Free space* siblings can be sized correctly.
struct ScanResult: Sendable {
    var id: ScanID
    var rootURL: URL
    var root: FSNode
    var volume: VolumeInfo?
    var startedAt: Date
    var finishedAt: Date
    var phase: ScanProgress.Phase
    var totalFiles: Int64
    var totalDirectories: Int64
    var totalBytes: Int64
}
