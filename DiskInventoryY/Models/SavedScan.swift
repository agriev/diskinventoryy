import Foundation

/// On-disk envelope for a saved `.dscan`. Schema versioned so future
/// readers can refuse / migrate older files.
struct SavedScan: Codable, Sendable {
    static let currentSchema: Int = 1

    var schema: Int
    var scannedAt: Date
    var rootURL: URL
    var volume: VolumeInfo?
    var tree: SerializedNode

    init(
        schema: Int = SavedScan.currentSchema,
        scannedAt: Date,
        rootURL: URL,
        volume: VolumeInfo?,
        tree: SerializedNode
    ) {
        self.schema = schema
        self.scannedAt = scannedAt
        self.rootURL = rootURL
        self.volume = volume
        self.tree = tree
    }
}

/// Codable mirror of `FSNode` with `parent` reconstructed on load.
struct SerializedNode: Codable, Sendable {
    var url: URL
    var displayName: String
    var kind: FSNodeKind
    var fileType: FileType
    var logicalSize: Int64
    var physicalSize: Int64
    var itemCount: Int32
    var kindID: FileKind.ID
    var isPackage: Bool
    var isMountPoint: Bool
    var mtime: Date?
    var flags: FSFlags
    var children: [SerializedNode]
}
