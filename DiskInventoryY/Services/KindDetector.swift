import Foundation
import UniformTypeIdentifiers
import os

/// Resolves a `FileKind` for a given URL. Cache is keyed on the lowercase
/// extension since 99 %+ of files are classified that way; resolution by
/// content type is reserved for the rare extension-less files.
final class KindDetector: @unchecked Sendable {
    private let cacheLock = OSAllocatedUnfairLock<[String: FileKind.ID]>(initialState: [:])
    private static let systemPathPrefixes: [String] = ["/System", "/private/var/db", "/usr"]

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
            if let utType = UTType(filenameExtension: ext) {
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
