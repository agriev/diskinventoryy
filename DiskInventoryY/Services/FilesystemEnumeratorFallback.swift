import Foundation

/// Foundation-only `FilesystemEnumerating`. Reads each directory in two
/// stages: `URL.contentsOfDirectory(...)` for names, then
/// `URLResourceValues` for sizes/types. Simple, portable, and the right
/// thing to fall back to when a bulk-syscall implementation can't run
/// (sandbox, sealed paths, tests).
struct FilesystemEnumeratorFallback: FilesystemEnumerating {
    private static let resourceKeys: Set<URLResourceKey> = [
        .nameKey,
        .fileResourceTypeKey,
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .isHiddenKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .contentModificationDateKey,
        .fileResourceIdentifierKey,
        .volumeIdentifierKey,
        .fileSecurityKey,
    ]

    func enumerate(directoryURL: URL) throws -> [FSEntry] {
        // Reject obviously-invalid roots up front so `Scanner` gets a
        // structured error instead of an opaque CocoaError later.
        if let isDir = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
           isDir == false {
            throw ScanError.notDirectory(directoryURL)
        }

        let fm = FileManager.default
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(Self.resourceKeys),
                options: [.skipsSubdirectoryDescendants]
            )
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain,
               error.code == NSFileReadNoPermissionError {
                throw ScanError.noAccess(directoryURL)
            }
            if let posix = error.userInfo[NSUnderlyingErrorKey] as? POSIXError,
               posix.code == .EACCES || posix.code == .EPERM {
                throw ScanError.noAccess(directoryURL)
            }
            throw ScanError.io(directoryURL, error)
        }

        var entries: [FSEntry] = []
        entries.reserveCapacity(urls.count)

        for url in urls {
            guard let entry = try self.makeEntry(for: url) else { continue }
            entries.append(entry)
        }
        return entries
    }

    private func makeEntry(for url: URL) throws -> FSEntry? {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: Self.resourceKeys)
        } catch {
            // Not fatal — emit a synthetic entry with the access flag.
            return FSEntry(
                url: url,
                name: url.lastPathComponent,
                fileType: .regularFile,
                logicalSize: 0,
                physicalSize: 0,
                mtime: nil,
                inode: nil,
                device: nil,
                hardlinkCount: 0,
                flags: [.accessDenied]
            )
        }

        let resourceType = values.fileResourceType
        var fileType: FileType = .regularFile
        var flags: FSFlags = []

        if values.isHidden ?? false { flags.insert(.hidden) }

        if values.isSymbolicLink ?? false {
            fileType = .symlink
            flags.insert(.symlink)
        } else if values.isPackage ?? false {
            fileType = .package
        } else if values.isDirectory ?? false {
            fileType = .directory
        } else if resourceType == .blockSpecial || resourceType == .characterSpecial {
            // Treat device nodes as regular files of zero size.
            fileType = .regularFile
        }

        let logical = Int64(values.fileSize ?? 0)
        let physical = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)

        return FSEntry(
            url: url,
            name: values.name ?? url.lastPathComponent,
            fileType: fileType,
            logicalSize: logical,
            physicalSize: physical,
            mtime: values.contentModificationDate,
            inode: nil,        // populated by the bulk variant only
            device: nil,
            hardlinkCount: 0,
            flags: flags
        )
    }
}
