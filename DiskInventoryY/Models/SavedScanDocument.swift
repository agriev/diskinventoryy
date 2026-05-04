import Foundation
import UniformTypeIdentifiers
import SwiftUI

extension UTType {
    /// Exported UTI registered in Info.plist for `.dscan` files.
    static let diskInventoryScan = UTType(exportedAs: "io.github.agriev.diskinventoryy.scan")
}

/// Lightweight `FileDocument` carrying an already-encoded `.dscan` blob.
/// We don't try to round-trip the FSNode tree through the SwiftUI
/// document pipeline — encoding/decoding happens in the caller, so this
/// type is really just a vessel for the bytes.
struct SavedScanDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.diskInventoryScan, .json] }
    static var writableContentTypes: [UTType] { [.diskInventoryScan] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = bytes
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
