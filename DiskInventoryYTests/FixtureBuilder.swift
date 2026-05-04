import Foundation
import XCTest

/// Builds throwaway directory trees in `FileManager.temporaryDirectory`
/// and tears them down on `tearDown`. Use from XCTestCase by holding it
/// in a stored property.
final class FixtureBuilder {
    private(set) var root: URL
    private let fm = FileManager.default

    init() throws {
        root = fm.temporaryDirectory
            .appendingPathComponent("DiskInventoryYTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? fm.removeItem(at: root)
    }

    /// Create a subdirectory at `relativePath` (supports `a/b/c`).
    @discardableResult
    func dir(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Create a file with the given byte count at `relativePath`.
    @discardableResult
    func file(_ relativePath: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data(repeating: 0xAB, count: bytes)
        try data.write(to: url)
        return url
    }

    /// Make a path effectively unreadable for the current user.
    func makeUnreadable(_ url: URL) throws {
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
    }

    func restorePermissions(_ url: URL) throws {
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Create a hardlink at `linkPath` pointing at `sourcePath` (both
    /// relative to fixture root).
    @discardableResult
    func hardlink(from sourcePath: String, to linkPath: String) throws -> URL {
        let source = root.appendingPathComponent(sourcePath)
        let target = root.appendingPathComponent(linkPath)
        try fm.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let r = link(source.path, target.path)
        if r != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return target
    }
}
