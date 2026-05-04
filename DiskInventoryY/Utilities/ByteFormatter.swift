import Foundation

/// Thin wrapper over `ByteCountFormatStyle`. Honors the `binary` /
/// `decimal` user preference at runtime.
enum ByteFormatter {
    enum Unit: String, Sendable {
        case binary  // 1 KiB = 1024 B
        case decimal // 1 KB  = 1000 B
    }

    static func format(_ bytes: Int64, unit: Unit = .binary) -> String {
        let style = ByteCountFormatStyle(
            style: unit == .binary ? .memory : .file,
            allowedUnits: .all,
            spellsOutZero: false,
            includesActualByteCount: false
        )
        return bytes.formatted(style)
    }
}
