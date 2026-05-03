import Foundation

/// Encodes / decodes `.dscan` files (JSON + zlib). The JSON is human-
/// debuggable on disk after `gunzip`; the wrapping reduces footprint
/// 5–10× for typical scans.
enum SavedScanCodec {

    enum CodecError: Error, CustomStringConvertible {
        case compressionFailed
        case decompressionFailed
        case schemaMismatch(found: Int, expected: Int)

        var description: String {
            switch self {
            case .compressionFailed:           return "Failed to compress saved scan"
            case .decompressionFailed:         return "Failed to decompress saved scan"
            case .schemaMismatch(let found, let expected):
                return "Saved scan schema \(found) is not supported (expected \(expected))"
            }
        }
    }

    static func encode(_ scan: SavedScan) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let raw = try encoder.encode(scan)
        do {
            let compressed = try (raw as NSData).compressed(using: .zlib)
            return compressed as Data
        } catch {
            throw CodecError.compressionFailed
        }
    }

    static func decode(_ data: Data) throws -> SavedScan {
        let raw: Data
        if let inflated = try? (data as NSData).decompressed(using: .zlib) {
            raw = inflated as Data
        } else {
            // Allow opening uncompressed JSON for debugging.
            raw = data
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scan = try decoder.decode(SavedScan.self, from: raw)
        guard scan.schema == SavedScan.currentSchema else {
            throw CodecError.schemaMismatch(found: scan.schema, expected: SavedScan.currentSchema)
        }
        return scan
    }

    // MARK: - Tree conversion helpers

    /// Convert an in-memory `FSNode` tree into the serializable mirror.
    static func snapshot(_ node: FSNode) -> SerializedNode {
        SerializedNode(
            url: node.url,
            displayName: node.displayName,
            kind: node.kind,
            fileType: node.fileType,
            logicalSize: node.logicalSize,
            physicalSize: node.physicalSize,
            itemCount: node.itemCount,
            kindID: node.kindID,
            isPackage: node.isPackage,
            isMountPoint: node.isMountPoint,
            mtime: node.mtime,
            flags: node.flags,
            children: node.children.map(snapshot)
        )
    }

    /// Inverse of `snapshot(_:)`. Reconstructs parent links so the
    /// resulting tree behaves like a freshly-scanned one.
    static func materialize(_ serialized: SerializedNode, depth: UInt8 = 0) -> FSNode {
        let inflatedChildren = serialized.children.map { materialize($0, depth: depth &+ 1) }
        let node = FSNode(
            url: serialized.url,
            displayName: serialized.displayName,
            kind: serialized.kind,
            fileType: serialized.fileType,
            logicalSize: serialized.logicalSize,
            physicalSize: serialized.physicalSize,
            itemCount: serialized.itemCount,
            parent: nil,
            children: [],
            kindID: serialized.kindID,
            isPackage: serialized.isPackage,
            isMountPoint: serialized.isMountPoint,
            depth: depth,
            mtime: serialized.mtime,
            flags: serialized.flags
        )
        node.setChildrenPreservingTotals(inflatedChildren)
        return node
    }
}
