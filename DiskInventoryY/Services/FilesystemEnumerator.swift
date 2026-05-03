import Foundation

/// Per-entry record produced by a `FilesystemEnumerating` walk.
/// Aggregation, package detection, and hardlink dedupe happen one
/// level up in the `Scanner`.
struct FSEntry: Sendable {
    var url: URL
    var name: String
    var fileType: FileType
    var logicalSize: Int64
    var physicalSize: Int64
    var mtime: Date?
    var inode: UInt64?
    var device: UInt64?
    var hardlinkCount: UInt32
    var flags: FSFlags
}

/// Abstract filesystem walker. Two implementations exist:
///   - `FilesystemEnumeratorFallback` — slower, sandbox-safe, uses
///     Foundation. Default until the bulk-syscall variant lands.
///   - (future) `FilesystemEnumeratorBulk` — `getattrlistbulk(2)` for
///     APFS-fast scans.
protocol FilesystemEnumerating: Sendable {
    /// Enumerate the immediate children of `directoryURL`. Implementers
    /// must not recurse — recursion is driven by the `Scanner`.
    /// Throws `ScanError.noAccess` for permission failures and
    /// `.notDirectory` if `directoryURL` is not a directory.
    func enumerate(directoryURL: URL) throws -> [FSEntry]
}
