import Foundation

/// Bit-set of secondary properties carried by an `FSNode`.
struct FSFlags: OptionSet, Sendable, Hashable, Codable {
    let rawValue: UInt16

    init(rawValue: UInt16) { self.rawValue = rawValue }

    static let symlink           = FSFlags(rawValue: 1 << 0)
    static let hidden            = FSFlags(rawValue: 1 << 1)
    static let firmlinkTarget    = FSFlags(rawValue: 1 << 2)
    static let hardlinkDuplicate = FSFlags(rawValue: 1 << 3)
    static let accessDenied      = FSFlags(rawValue: 1 << 4)
}
