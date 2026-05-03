import Foundation

/// A coarse bucket used to color the treemap and group statistics.
/// `id` is a stable identifier (e.g. `"image"`) — the curated palette
/// keys off it, so introducing a new kind never recolors existing ones.
struct FileKind: Hashable, Identifiable, Sendable, Codable {
    typealias ID = String

    let id: ID
    let displayName: String
    /// Bucket priority when more than one matches. Lower wins.
    let priority: Int
}

extension FileKind {
    static let image       = FileKind(id: "image",       displayName: "Images",       priority: 10)
    static let video       = FileKind(id: "video",       displayName: "Movies",       priority: 20)
    static let audio       = FileKind(id: "audio",       displayName: "Audio",        priority: 30)
    static let document    = FileKind(id: "document",    displayName: "Documents",    priority: 40)
    static let archive     = FileKind(id: "archive",     displayName: "Archives",     priority: 50)
    static let code        = FileKind(id: "code",        displayName: "Code",         priority: 60)
    static let application = FileKind(id: "application", displayName: "Applications", priority: 70)
    static let package     = FileKind(id: "package",     displayName: "Packages",     priority: 80)
    static let system      = FileKind(id: "system",      displayName: "System",       priority: 90)
    static let other       = FileKind(id: "other",       displayName: "Other",        priority: 1_000)

    static let allKnown: [FileKind] = [
        .image, .video, .audio, .document, .archive,
        .code, .application, .package, .system, .other,
    ]
}
