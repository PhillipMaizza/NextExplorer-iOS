@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("FileCategory")
struct FileCategoryTests {
    @Test("a directory buckets as folder regardless of its kind or name")
    func directoryIsFolder() {
        #expect(FileCategory.of(kind: FileItem.directoryKind, isDirectory: true) == .folder)
        #expect(FileCategory.of(kind: TestKind.photo, isDirectory: true) == .folder)
    }

    @Test("image and raw image extensions bucket as image")
    func images() {
        #expect(FileCategory.of(kind: TestKind.photo, isDirectory: false) == .image)
        #expect(FileCategory.of(kind: "PNG", isDirectory: false) == .image)
        #expect(FileCategory.of(kind: "heic", isDirectory: false) == .image)
        #expect(FileCategory.of(kind: "dng", isDirectory: false) == .image)
    }

    @Test("video and audio extensions bucket into their own categories")
    func videoAndAudio() {
        #expect(FileCategory.of(kind: TestKind.video, isDirectory: false) == .video)
        #expect(FileCategory.of(kind: "MKV", isDirectory: false) == .video)
        #expect(FileCategory.of(kind: "mp3", isDirectory: false) == .audio)
        #expect(FileCategory.of(kind: "flac", isDirectory: false) == .audio)
    }

    @Test("archives bucket as archive")
    func archives() {
        #expect(FileCategory.of(kind: "zip", isDirectory: false) == .archive)
        #expect(FileCategory.of(kind: "7z", isDirectory: false) == .archive)
    }

    @Test("pdf, office and text/code kinds bucket as document")
    func documents() {
        #expect(FileCategory.of(kind: TestKind.pdf, isDirectory: false) == .document)
        #expect(FileCategory.of(kind: "docx", isDirectory: false) == .document)
        #expect(FileCategory.of(kind: TestKind.text, isDirectory: false) == .document)
        #expect(FileCategory.of(kind: "swift", isDirectory: false) == .document)
        #expect(FileCategory.of(kind: "JSON", isDirectory: false) == .document)
    }

    @Test("unrecognised and binary kinds fall through to other")
    func other() {
        #expect(FileCategory.of(kind: "exe", isDirectory: false) == .other)
        #expect(FileCategory.of(kind: "dylib", isDirectory: false) == .other)
        #expect(FileCategory.of(kind: "", isDirectory: false) == .other)
        #expect(FileCategory.of(kind: "wat", isDirectory: false) == .other)
    }
}
