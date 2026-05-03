import Foundation

/// Errors raised by the scanner. Wrapped IO errors keep the underlying
/// `errno`/`POSIXError` accessible via `.io(_)`.
enum ScanError: Error, Sendable, CustomStringConvertible {
    case noAccess(URL)
    case notDirectory(URL)
    case io(URL, any Error)
    case cancelled

    var description: String {
        switch self {
        case .noAccess(let url):    return "No access: \(url.path)"
        case .notDirectory(let url): return "Not a directory: \(url.path)"
        case .io(let url, let err):  return "I/O error at \(url.path): \(err)"
        case .cancelled:            return "Scan cancelled"
        }
    }
}
