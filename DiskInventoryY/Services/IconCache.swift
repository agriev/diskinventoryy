import AppKit
import Foundation
import os

/// Cached `NSWorkspace` icons keyed on lowercase extension. The cache
/// is bounded loosely — a typical scan touches < 500 distinct
/// extensions, so we don't bother evicting.
final class IconCache: @unchecked Sendable {
    static let shared = IconCache()

    private let lock = OSAllocatedUnfairLock<[String: NSImage]>(initialState: [:])
    private let folderIcon: NSImage
    private let bundleIcon: NSImage
    private let symlinkIcon: NSImage
    private let mountIcon: NSImage

    init() {
        folderIcon = NSWorkspace.shared.icon(forFile: "/")
        bundleIcon = NSWorkspace.shared.icon(forFile: "/Applications")
        symlinkIcon = NSWorkspace.shared.icon(forFile: "/etc")
        mountIcon = NSWorkspace.shared.icon(forFile: "/Volumes")
    }

    func icon(for node: FSNode, size: CGSize = CGSize(width: 16, height: 16)) -> NSImage {
        let resolved: NSImage
        switch node.fileType {
        case .directory, .mountPoint:
            resolved = node.fileType == .mountPoint ? mountIcon : folderIcon
        case .package:
            resolved = bundleIcon
        case .symlink:
            resolved = symlinkIcon
        case .synthetic:
            resolved = folderIcon
        case .regularFile:
            let ext = node.url.pathExtension.lowercased()
            resolved = iconForExtension(ext)
        }
        let copy = resolved.copy() as? NSImage ?? resolved
        copy.size = size
        return copy
    }

    private func iconForExtension(_ ext: String) -> NSImage {
        if ext.isEmpty {
            return NSWorkspace.shared.icon(forFile: "/usr/bin/true")
        }
        return lock.withLock { cache -> NSImage in
            if let hit = cache[ext] { return hit }
            // `icon(forFileType:)` accepts both extensions and UTI strings.
            let icon = NSWorkspace.shared.icon(forFileType: ext)
            cache[ext] = icon
            return icon
        }
    }
}
