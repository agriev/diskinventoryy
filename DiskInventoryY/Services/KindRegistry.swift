import Foundation
import UniformTypeIdentifiers

/// Static, ordered list of `FileKind` buckets and the rule that maps a
/// `UTType` to one of them. Order matters: a JPEG conforms to both
/// `.image` and `.data`, so we check the more specific buckets first.
enum KindRegistry {
    static let allKinds: [FileKind] = FileKind.allKnown

    /// Map a `UTType` to the most specific known bucket, or `.other`.
    /// Order matters: source code conforms to `.text`, so the `code`
    /// bucket must be checked before `document`.
    static func bucket(for type: UTType) -> FileKind {
        if type.conforms(to: .image)            { return .image }
        if type.conforms(to: .movie)            { return .video }
        if type.conforms(to: .video)            { return .video }
        if type.conforms(to: .audio)            { return .audio }
        if type.conforms(to: .archive)          { return .archive }
        if type.conforms(to: .sourceCode)       { return .code }
        if type.conforms(to: .script)           { return .code }
        if type.conforms(to: .shellScript)      { return .code }
        if conformsToAnyDocument(type)          { return .document }
        if type.conforms(to: .application)      { return .application }
        if type.conforms(to: .applicationBundle){ return .application }
        return .other
    }

    private static let documentTypes: [UTType] = [
        .pdf, .text, .plainText, .rtf, .html, .xml, .json,
        .spreadsheet, .presentation,
    ]

    private static func conformsToAnyDocument(_ type: UTType) -> Bool {
        documentTypes.contains(where: { type.conforms(to: $0) })
    }
}
