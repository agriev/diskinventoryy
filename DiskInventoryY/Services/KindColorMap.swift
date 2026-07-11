import AppKit
import SwiftUI

/// Per-scan mapping of file kind → color, reproducing the original
/// Disk Inventory X scheme (FileTypeColors.m): a fixed 12-color
/// palette handed out to kinds in rank order, then a grayscale ramp
/// once the palette is exhausted.
///
/// DIX assigned palette slots in the order kinds were first
/// encountered; we assign by descending total size instead — same
/// visual language ("the dominant kind is blue, the next is red"),
/// but deterministic for a given tree.
struct KindColorMap: Equatable, Sendable {
    private struct RGB: Equatable, Sendable {
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat
    }

    /// Verbatim from Disk Inventory X `FileTypeColors.m`:
    /// six pure primaries/secondaries, then their 0.58-lightened twins.
    static let dixPalette: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0, 0, 1),          // blue
        (1, 0, 0),          // red
        (0, 1, 0),          // green
        (0, 1, 1),          // cyan
        (1, 0, 1),          // magenta
        (1, 1, 0),          // yellow
        (0.58, 0.58, 1),    // light blue
        (1, 0.58, 0.58),    // light red
        (0.58, 1, 0.58),    // light green
        (0.58, 1, 1),       // light cyan
        (1, 0.58, 1),       // light magenta
        (1, 1, 0.58),       // light yellow
    ]

    private var storage: [FileKind.ID: RGB]

    /// Build a map by handing out palette slots to `rankedKindIDs`
    /// in order (callers pass kinds sorted by descending total size).
    /// Kinds past the 12-color palette get DIX's grayscale ramp:
    /// `white = min(0.9, 0.05 * index)`. Synthetic Free/Other space
    /// are pinned to fixed greys and never consume a palette slot.
    init(rankedKindIDs: [FileKind.ID]) {
        var map: [FileKind.ID: RGB] = [
            FileKind.freeSpace.id:  RGB(r: 0.78, g: 0.78, b: 0.78),
            FileKind.otherSpace.id: RGB(r: 0.55, g: 0.55, b: 0.55),
        ]
        var slot = 0
        for id in rankedKindIDs where map[id] == nil {
            if slot < Self.dixPalette.count {
                let c = Self.dixPalette[slot]
                map[id] = RGB(r: c.r, g: c.g, b: c.b)
            } else {
                let white = min(0.9, 0.05 * CGFloat(slot))
                map[id] = RGB(r: white, g: white, b: white)
            }
            slot += 1
        }
        storage = map
    }

    /// Stable assignment used before any scan finishes (empty window,
    /// previews): palette in `FileKind.allKnown` priority order.
    static let fallback = KindColorMap(
        rankedKindIDs: FileKind.allKnown.map(\.id)
    )

    func nsColor(for id: FileKind.ID) -> NSColor {
        if let rgb = storage[id] {
            return NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        }
        // Kind not present when the map was built (e.g. appeared via
        // subtree refresh) — deterministic FNV hue, same fallback the
        // static palette used.
        let h = ColorPalette.fnv1aHash(id)
        let hue = CGFloat(h % 360) / 360.0
        return NSColor(deviceHue: hue, saturation: 0.9, brightness: 1.0, alpha: 1.0)
    }

    /// SwiftUI bridge.
    func color(for id: FileKind.ID) -> Color {
        Color(nsColor: nsColor(for: id))
    }
}

// MARK: - Environment plumbing

private struct KindColorsKey: EnvironmentKey {
    static let defaultValue = KindColorMap.fallback
}

extension EnvironmentValues {
    /// The active per-scan kind→color assignment. Set by `RootView`
    /// once a scan completes; every color consumer (treemap, outline
    /// swatches, kinds bar, inspector) reads this instead of a global.
    var kindColors: KindColorMap {
        get { self[KindColorsKey.self] }
        set { self[KindColorsKey.self] = newValue }
    }
}
