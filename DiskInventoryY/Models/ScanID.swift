import Foundation

/// Stable identity of a single scan / window. Used as the `Hashable`
/// token for `WindowGroup(for: ScanID.self)` so scans persist across
/// restoration.
struct ScanID: Hashable, Sendable, Codable, CustomStringConvertible {
    let value: UUID

    init(_ value: UUID = UUID()) {
        self.value = value
    }

    var description: String { value.uuidString }
}
