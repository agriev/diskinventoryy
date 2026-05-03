import AppKit
import Foundation

/// Best-effort probe for Full Disk Access on macOS 14+. Reads a known
/// TCC-protected path; an `EPERM` (or POSIX equivalent) is treated as
/// "FDA not granted." Probing is cheap and side-effect-free.
enum PermissionsProbe {
    /// Path probed for Full Disk Access. `~/Library/Mail` is a long-
    /// standing TCC-gated location that exists on every fresh install.
    static let probedPath = NSString(string: "~/Library/Mail").expandingTildeInPath

    static func hasFullDiskAccess() -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: probedPath)
            return true
        } catch {
            return false
        }
    }

    /// Opens System Settings → Privacy & Security → Full Disk Access.
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
