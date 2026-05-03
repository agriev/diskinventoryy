import Foundation

/// Distinguishes the three node varieties that can appear in a treemap:
/// real filesystem entries, the synthetic *Other* bucket (purgeable,
/// snapshots, paths denied by TCC), and the *Free space* sibling drawn at
/// the volume root.
enum FSNodeKind: String, Sendable, Codable, Hashable {
    case regular
    case otherSpace
    case freeSpace
}

/// What a real filesystem node refers to. `synthetic` is reserved for
/// `FSNodeKind.otherSpace` and `.freeSpace`.
enum FileType: String, Sendable, Codable, Hashable {
    case directory
    case regularFile
    case symlink
    case package
    case mountPoint
    case synthetic
}
