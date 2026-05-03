import Foundation

/// Thin wrapper over `ByteCountFormatStyle`. Default style mirrors
/// what Finder shows in column view (decimal, file-style).
enum ByteFormatter {
    static let file = ByteCountFormatStyle(
        style: .file,
        allowedUnits: .all,
        spellsOutZero: false,
        includesActualByteCount: false
    )

    static func format(_ bytes: Int64) -> String {
        bytes.formatted(file)
    }
}
