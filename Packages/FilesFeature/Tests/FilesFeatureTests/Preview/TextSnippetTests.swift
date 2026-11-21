@testable import FilesFeature
import Foundation
import Testing

struct TextSnippetTests {
    private func snippet(_ text: String) -> String? {
        TextSnippet.make(from: Data(text.utf8))
    }

    @Test("A text file shows its first lines as they are")
    func showsTheFirstLines() {
        #expect(snippet("import SwiftUI\n\nstruct A {}\n") == "import SwiftUI\n\nstruct A {}")
    }

    @Test("Windows and old Mac line endings become line breaks")
    func normalizesLineEndings() {
        #expect(snippet("one\r\ntwo\rthree") == "one\ntwo\nthree")
    }

    @Test("Tabs are drawn as two spaces so indentation stays narrow")
    func narrowsTabs() {
        #expect(snippet("a\n\tb") == "a\n  b")
    }

    @Test("Blank lines before the first text and after the last are dropped")
    func trimsBlankEdges() {
        #expect(snippet("\n\n  \nfirst\nlast\n\n\n") == "first\nlast")
    }

    @Test("Only the first twelve lines are kept")
    func keepsTwelveLines() {
        let lines = (1 ... 30).map { "line \($0)" }
        #expect(snippet(lines.joined(separator: "\n"))?.split(separator: "\n").count == 12)
    }

    @Test("A long line is cut at forty characters")
    func cutsLongLines() {
        #expect(snippet(String(repeating: "x", count: 100))?.count == 40)
    }

    @Test("Bytes with a NUL are not text")
    func rejectsNul() {
        #expect(TextSnippet.make(from: Data([0x68, 0x69, 0x00, 0x21])) == nil)
    }

    @Test("Bytes that mostly do not decode are not text")
    func rejectsMostlyUndecodable() {
        #expect(TextSnippet.make(from: Data(repeating: 0xFF, count: 64)) == nil)
    }

    @Test("A file of only blank space has nothing to show")
    func rejectsBlank() {
        #expect(snippet(" \n\t\n  ") == nil)
        #expect(snippet("") == nil)
    }

    @Test("Unicode text, including emoji, is kept")
    func keepsUnicode() {
        #expect(snippet("héllo 日本語 🎉") == "héllo 日本語 🎉")
    }

    @Test("A sample cut inside a multibyte character drops the broken character")
    func dropsATornCharacter() {
        let text = String(repeating: "a", count: 4095) + "é"
        #expect(snippet(text)?.contains("\u{FFFD}") == false)
    }

    @Test("Text and code kinds draw their own thumbnail, other files do not", arguments: [
        ("txt", true), ("swift", true), ("md", true), ("json", true),
        ("jpg", false), ("mp4", false), ("zip", false), ("pdf", false), ("mp3", false),
    ])
    func recognisesTextKinds(kind: String, isText: Bool) {
        #expect(TextSnippet.isTextKind(kind) == isText)
    }

    @Test("Audio and text files read their own content for a thumbnail")
    func shouldReadOwnContent() {
        #expect(ThumbnailImage.shouldReadOwnContent(kind: "mp3"))
        #expect(ThumbnailImage.shouldReadOwnContent(kind: "swift"))
        #expect(!ThumbnailImage.shouldReadOwnContent(kind: "jpg"))
        #expect(!ThumbnailImage.shouldReadOwnContent(kind: "mp4"))
    }
}
