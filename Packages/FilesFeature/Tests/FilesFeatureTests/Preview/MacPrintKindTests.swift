#if os(macOS)
    @testable import FilesFeature
    import Testing
    import TestUtils

    struct MacPrintKindTests {
        @Test
        func printableTypesAreRecognizedFromTheExtension() {
            #expect(MacPrintKind(fileName: TestFile.report) == .pdf)
            #expect(MacPrintKind(fileName: "photo.JPG") == .image)
            #expect(MacPrintKind(fileName: TestFile.notes) == .text)
            #expect(MacPrintKind(fileName: "main.swift") == .text)
            #expect(MacPrintKind(fileName: "data.json") == .text)
        }

        @Test
        func otherTypesAreNotPrintable() {
            #expect(MacPrintKind(fileName: "movie.mp4") == nil)
            #expect(MacPrintKind(fileName: "archive.zip") == nil)
            #expect(MacPrintKind(fileName: "no-extension") == nil)
        }
    }
#endif
