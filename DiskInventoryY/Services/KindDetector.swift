import Foundation
import UniformTypeIdentifiers
import os

/// Resolves a `FileKind` for a given URL. Cache is keyed on the lowercase
/// extension since 99 %+ of files are classified that way; resolution by
/// content type is reserved for the rare extension-less files.
final class KindDetector: @unchecked Sendable {
    private let cacheLock = OSAllocatedUnfairLock<[String: FileKind.ID]>(initialState: [:])
    private static let systemPathPrefixes: [String] = ["/System", "/private/var/db", "/usr"]

    /// Hardcoded fallback for extensions whose UTI conformance varies
    /// across SDKs. Checked before `UTType(filenameExtension:)`, so it
    /// overrides system answers too.
    private static let extensionOverrides: [String: FileKind.ID] = [
        // Video containers/codecs that don't always conform to .movie
        // on older SDKs.
        "mkv":  FileKind.video.id,
        "webm": FileKind.video.id,
        "flv":  FileKind.video.id,
        "ogv":  FileKind.video.id,
        // Common code extensions whose UTType may be unknown.
        "go":   FileKind.code.id,
        "rs":   FileKind.code.id,
        "kt":   FileKind.code.id,
        "kts":  FileKind.code.id,
        "lua":  FileKind.code.id,
        "ts":   FileKind.code.id,
        "tsx":  FileKind.code.id,
        "jsx":  FileKind.code.id,
        "vue":  FileKind.code.id,
        "zig":  FileKind.code.id,
        "dart": FileKind.code.id,
        "ex":   FileKind.code.id,
        "exs":  FileKind.code.id,
        "elm":  FileKind.code.id,
        "nim":  FileKind.code.id,
        "v":    FileKind.code.id,
        "sol":  FileKind.code.id,
        // Configs / data files that aren't natively typed.
        "yml":   FileKind.document.id,
        "yaml":  FileKind.document.id,
        "toml":  FileKind.document.id,
        "ini":   FileKind.document.id,
        "log":   FileKind.document.id,
        "csv":   FileKind.document.id,
        "tsv":   FileKind.document.id,
    ]

    func kind(forURL url: URL, fileType: FileType, isPackage: Bool) -> FileKind.ID {
        if isPackage {
            return FileKind.package.id
        }
        if Self.isSystemPath(url) {
            return FileKind.system.id
        }
        switch fileType {
        case .directory, .mountPoint, .synthetic, .symlink:
            return FileKind.other.id
        default:
            break
        }

        let ext = url.pathExtension.lowercased()
        if ext.isEmpty {
            return FileKind.other.id
        }

        return cacheLock.withLock { cache -> FileKind.ID in
            if let hit = cache[ext] { return hit }
            let resolved: FileKind.ID
            if let override = Self.extensionOverrides[ext] {
                resolved = override
            } else if let utType = UTType(filenameExtension: ext) {
                resolved = KindRegistry.bucket(for: utType).id
            } else {
                resolved = FileKind.other.id
            }
            cache[ext] = resolved
            return resolved
        }
    }

    private static func isSystemPath(_ url: URL) -> Bool {
        let path = url.path
        return systemPathPrefixes.contains(where: { path.hasPrefix($0) })
    }
}
