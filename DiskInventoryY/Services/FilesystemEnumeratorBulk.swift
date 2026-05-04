import Foundation
import Darwin

/// `getattrlistbulk(2)`-backed enumerator. Issues one syscall per
/// directory and parses a packed attribute buffer for batches of
/// entries — typically 5–20× faster than `FileManager.enumerator`
/// for big trees on APFS.
///
/// Falls back to throwing `ScanError.noAccess` / `.notDirectory`
/// for the same error conditions the Foundation variant surfaces, so
/// callers can swap implementations transparently.
struct FilesystemEnumeratorBulk: FilesystemEnumerating {

    /// Single chunk requested per syscall. 64 KB fits ~200 entries on
    /// a typical APFS directory; bumping it past 256 KB doesn't help.
    private static let bufferSize = 64 * 1024

    func enumerate(directoryURL: URL) throws -> [FSEntry] {
        let path = directoryURL.path
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else {
            let err = errno
            if err == EACCES || err == EPERM {
                throw ScanError.noAccess(directoryURL)
            }
            if err == ENOTDIR {
                throw ScanError.notDirectory(directoryURL)
            }
            throw ScanError.io(directoryURL, POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO))
        }
        defer { close(fd) }

        // Verify it's a directory; bulk on a regular file silently
        // returns 0 entries which would mask user-visible issues.
        var st = stat()
        if fstat(fd, &st) != 0 || (st.st_mode & S_IFMT) != S_IFDIR {
            throw ScanError.notDirectory(directoryURL)
        }

        var attrList = attrlist()
        attrList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attrList.commonattr =
            attrgroup_t(ATTR_CMN_RETURNED_ATTRS) |
            attrgroup_t(ATTR_CMN_NAME) |
            attrgroup_t(ATTR_CMN_OBJTYPE) |
            attrgroup_t(ATTR_CMN_FILEID) |
            attrgroup_t(ATTR_CMN_MODTIME)
        attrList.fileattr =
            attrgroup_t(ATTR_FILE_DATALENGTH) |
            attrgroup_t(ATTR_FILE_ALLOCSIZE)

        var entries: [FSEntry] = []
        var buffer = [UInt8](repeating: 0, count: Self.bufferSize)

        while true {
            let returned = buffer.withUnsafeMutableBufferPointer { buf -> Int in
                guard let base = buf.baseAddress else { return -1 }
                let r = getattrlistbulk(fd, &attrList,
                                         UnsafeMutableRawPointer(base),
                                         Self.bufferSize, 0)
                return Int(r)
            }
            if returned == 0 { break }
            if returned < 0 {
                let err = errno
                throw ScanError.io(directoryURL,
                                   POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO))
            }

            try buffer.withUnsafeBytes { raw -> Void in
                var offset = 0
                for _ in 0..<returned {
                    guard offset + 4 <= raw.count else { break }
                    let entryLen = Int(raw.loadUnaligned(fromByteOffset: offset,
                                                          as: UInt32.self))
                    if entryLen <= 0 { break }
                    let entryStart = offset
                    let attrsStart = offset + 4

                    if let entry = try parseEntry(rawBuffer: raw,
                                                   attrsStart: attrsStart,
                                                   entryEnd: entryStart + entryLen,
                                                   directoryURL: directoryURL) {
                        entries.append(entry)
                    }
                    offset = entryStart + entryLen
                }
            }
        }

        return entries
    }

    // MARK: - Buffer parsing

    /// Parse one entry's attribute fields. The fields must be read in
    /// the same order as their bits in the requested attrlist; macOS
    /// also tells us via `ATTR_CMN_RETURNED_ATTRS` which fields it
    /// actually filled in this round, so we honour that too.
    private func parseEntry(
        rawBuffer raw: UnsafeRawBufferPointer,
        attrsStart: Int,
        entryEnd: Int,
        directoryURL: URL
    ) throws -> FSEntry? {
        // attribute_set_t == 5 × UInt32 = 20 bytes (matches ATTR_BIT_MAP_COUNT).
        guard attrsStart + 20 <= raw.count else { return nil }
        let returnedCommon = raw.loadUnaligned(fromByteOffset: attrsStart,
                                                as: UInt32.self)
        // returnedCommon is the first u32; volattr/dirattr/fileattr/forkattr follow.
        let returnedFile = raw.loadUnaligned(fromByteOffset: attrsStart + 12,
                                              as: UInt32.self)

        var cursor = attrsStart + 20

        var name: String?
        var fileType: FileType = .regularFile
        var inode: UInt64 = 0
        var mtime: Date?
        var dataLength: Int64 = 0
        var allocSize: Int64 = 0

        // ATTR_CMN_NAME — `attrreference_t { int32 dataoffset; uint32 length }`
        // dataoffset is from the start of the reference field itself.
        if returnedCommon & UInt32(ATTR_CMN_NAME) != 0 {
            guard cursor + 8 <= raw.count else { return nil }
            let dataOffset = Int(raw.loadUnaligned(fromByteOffset: cursor,
                                                    as: Int32.self))
            let length = Int(raw.loadUnaligned(fromByteOffset: cursor + 4,
                                                as: UInt32.self))
            let nameStart = cursor + dataOffset
            let nameLen = max(0, length - 1)   // strip trailing NUL
            if nameStart >= 0,
               nameStart + nameLen <= raw.count,
               nameLen > 0,
               let nameBytes = raw.baseAddress?.advanced(by: nameStart) {
                let bufferPointer = UnsafeBufferPointer(
                    start: nameBytes.assumingMemoryBound(to: UInt8.self),
                    count: nameLen
                )
                name = String(decoding: bufferPointer, as: UTF8.self)
            }
            cursor += 8
        }

        if returnedCommon & UInt32(ATTR_CMN_OBJTYPE) != 0 {
            guard cursor + 4 <= raw.count else { return nil }
            let objType = raw.loadUnaligned(fromByteOffset: cursor, as: UInt32.self)
            // From <sys/vnode.h>: VREG=1, VDIR=2, VLNK=5, VBLK=6, VCHR=7, VSOCK=8, VFIFO=9.
            switch objType {
            case 2:  fileType = .directory
            case 5:  fileType = .symlink
            default: fileType = .regularFile
            }
            cursor += 4
        }

        // Buffer order matches *bit value*, low → high. MODTIME
        // (0x00000400) comes before FILEID (0x02000000).
        if returnedCommon & UInt32(ATTR_CMN_MODTIME) != 0 {
            guard cursor + 16 <= raw.count else { return nil }
            // struct timespec on macOS 64-bit is { int64 tv_sec; int64 tv_nsec }.
            let secs = raw.loadUnaligned(fromByteOffset: cursor, as: Int64.self)
            let nsec = raw.loadUnaligned(fromByteOffset: cursor + 8, as: Int64.self)
            mtime = Date(timeIntervalSince1970: TimeInterval(secs)
                         + TimeInterval(nsec) / 1_000_000_000)
            cursor += 16
        }

        if returnedCommon & UInt32(ATTR_CMN_FILEID) != 0 {
            guard cursor + 8 <= raw.count else { return nil }
            inode = raw.loadUnaligned(fromByteOffset: cursor, as: UInt64.self)
            cursor += 8
        }

        // ATTR_FILE_ALLOCSIZE (bit 0x4) precedes ATTR_FILE_DATALENGTH (0x200).
        if returnedFile & UInt32(ATTR_FILE_ALLOCSIZE) != 0 {
            guard cursor + 8 <= raw.count else { return nil }
            allocSize = raw.loadUnaligned(fromByteOffset: cursor, as: Int64.self)
            cursor += 8
        }

        if returnedFile & UInt32(ATTR_FILE_DATALENGTH) != 0 {
            guard cursor + 8 <= raw.count else { return nil }
            dataLength = raw.loadUnaligned(fromByteOffset: cursor, as: Int64.self)
            cursor += 8
        }

        guard let entryName = name, !entryName.isEmpty else { return nil }
        if entryName == "." || entryName == ".." { return nil }

        let url = directoryURL.appendingPathComponent(entryName)
        var flags: FSFlags = []
        if entryName.hasPrefix(".") { flags.insert(.hidden) }
        if fileType == .symlink { flags.insert(.symlink) }

        // Bulk enumeration doesn't surface bundle-package status — we
        // leave package detection to the Foundation pass on directory
        // entries that the Scanner specifically asks about.
        return FSEntry(
            url: url,
            name: entryName,
            fileType: fileType,
            logicalSize: dataLength,
            physicalSize: allocSize > 0 ? allocSize : dataLength,
            mtime: mtime,
            inode: inode == 0 ? nil : inode,
            device: nil,
            hardlinkCount: 0,
            flags: flags
        )
    }
}
