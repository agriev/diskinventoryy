import AppKit
import SwiftUI

/// Maps `FileKind.id` to a stable `NSColor`. Curated for the known kinds;
/// unknown ids fall through to a deterministic FNV-1a-derived hue so the
/// same id always produces the same color on every machine and run.
struct ColorPalette: Sendable {
    static let shared = ColorPalette()

    private let curatedLight: [FileKind.ID: NSColor] = [
        FileKind.image.id:       .systemPurple,
        FileKind.video.id:       .systemPink,
        FileKind.audio.id:       .systemOrange,
        FileKind.document.id:    .systemBlue,
        FileKind.archive.id:     .systemBrown,
        FileKind.code.id:        .systemGreen,
        FileKind.application.id: .systemTeal,
        FileKind.package.id:     .systemTeal,
        FileKind.system.id:      .systemGray,
        FileKind.other.id:       .systemYellow,
        FileKind.freeSpace.id:   NSColor(white: 0.78, alpha: 1.0),
        FileKind.otherSpace.id:  NSColor(white: 0.55, alpha: 1.0),
    ]

    /// Color for the given kind id. Resolves dynamic light/dark via the
    /// returned `NSColor`; cushion shading reduces saturation in dark mode
    /// inside the treemap renderer.
    func nsColor(for id: FileKind.ID) -> NSColor {
        if let curated = curatedLight[id] {
            return curated
        }
        return Self.deterministicColor(for: id)
    }

    /// SwiftUI bridge.
    func color(for id: FileKind.ID) -> Color {
        Color(nsColor: nsColor(for: id))
    }

    // MARK: - FNV-1a fallback

    /// Hash an id with FNV-1a (32-bit) so output is stable across processes
    /// and Swift versions — Swift's `String.hashValue` seeds per-process.
    static func fnv1aHash(_ string: String) -> UInt32 {
        var hash: UInt32 = 0x811c_9dc5
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash &*= 0x0100_0193
        }
        return hash
    }

    private static func deterministicColor(for id: FileKind.ID) -> NSColor {
        let h = fnv1aHash(id)
        let hue = CGFloat(h % 360) / 360.0
        return NSColor(deviceHue: hue, saturation: 0.55, brightness: 0.85, alpha: 1.0)
    }
}
