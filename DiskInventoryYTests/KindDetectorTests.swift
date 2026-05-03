import XCTest
@testable import DiskInventoryY

final class KindDetectorTests: XCTestCase {

    private let detector = KindDetector()

    private func kind(_ name: String, type: FileType = .regularFile, isPackage: Bool = false) -> FileKind.ID {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        return detector.kind(forURL: url, fileType: type, isPackage: isPackage)
    }

    func testImageExtensions() {
        XCTAssertEqual(kind("photo.jpg"), FileKind.image.id)
        XCTAssertEqual(kind("logo.png"), FileKind.image.id)
        XCTAssertEqual(kind("icon.heic"), FileKind.image.id)
        XCTAssertEqual(kind("graphic.svg"), FileKind.image.id)
    }

    func testVideoExtensions() {
        XCTAssertEqual(kind("clip.mp4"), FileKind.video.id)
        XCTAssertEqual(kind("movie.mov"), FileKind.video.id)
        XCTAssertEqual(kind("stream.mkv"), FileKind.video.id)
    }

    func testAudioExtensions() {
        XCTAssertEqual(kind("song.mp3"), FileKind.audio.id)
        XCTAssertEqual(kind("track.wav"), FileKind.audio.id)
        XCTAssertEqual(kind("podcast.m4a"), FileKind.audio.id)
    }

    func testDocumentExtensions() {
        XCTAssertEqual(kind("manual.pdf"), FileKind.document.id)
        XCTAssertEqual(kind("notes.txt"), FileKind.document.id)
    }

    func testArchiveExtensions() {
        XCTAssertEqual(kind("backup.zip"), FileKind.archive.id)
        XCTAssertEqual(kind("artifact.tar.gz"), FileKind.archive.id)
    }

    func testCodeExtensions() {
        XCTAssertEqual(kind("main.swift"), FileKind.code.id)
        XCTAssertEqual(kind("script.py"), FileKind.code.id)
        XCTAssertEqual(kind("util.c"), FileKind.code.id)
    }

    func testFileWithoutExtensionFallsBackToOther() {
        XCTAssertEqual(kind("README"), FileKind.other.id)
        XCTAssertEqual(kind("Makefile"), FileKind.other.id)
    }

    func testPackageBeatsExtensionMatching() {
        XCTAssertEqual(kind("Foo.app", type: .package, isPackage: true), FileKind.package.id)
    }

    func testDirectoryReturnsOther() {
        XCTAssertEqual(kind("subdir", type: .directory), FileKind.other.id)
    }

    func testSystemPathReturnsSystemKind() {
        let url = URL(fileURLWithPath: "/System/Library/Frameworks/AppKit.framework/AppKit")
        XCTAssertEqual(detector.kind(forURL: url, fileType: .regularFile, isPackage: false),
                       FileKind.system.id)
    }

    func testCacheReturnsConsistentResults() {
        let first = kind("photo.jpg")
        let second = kind("photo.jpg")
        let third = kind("PHOTO.JPG") // canonicalized to lowercase
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, third)
    }
}
