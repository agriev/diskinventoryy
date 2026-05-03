import Foundation

/// Snapshot of the volume that hosts a scan root. All sizes are bytes.
/// `availableForImportant` reflects the macOS-preferred "free space" —
/// it factors purgeable storage on APFS.
struct VolumeInfo: Hashable, Sendable, Codable {
    var name: String
    var url: URL
    var fileSystemType: String?
    var totalCapacity: Int64
    var availableCapacity: Int64
    var availableForImportant: Int64
    var isRemovable: Bool
    var isLocal: Bool
    var isReadOnly: Bool
}
