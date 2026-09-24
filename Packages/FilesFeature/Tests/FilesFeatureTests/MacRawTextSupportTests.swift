#if os(macOS)
    @testable import FilesFeature
    import Testing

    struct MacRawTextSupportTests {
        @Test("text and source files can be viewed as text", arguments: ["notes.txt", "README.md", "app.swift", "data.json", "page.html", "config.yaml"])
        func textFiles(name: String) {
            #expect(MacRawTextSupport.applies(toFileNamed: name))
        }

        @Test("files with no extension count as text", arguments: ["Makefile", "Dockerfile", "README"])
        func extensionless(name: String) {
            #expect(MacRawTextSupport.applies(toFileNamed: name))
        }

        @Test("binary files only offer Open With", arguments: ["photo.jpg", "movie.mp4", "report.pdf", "archive.zip", "disk.dmg", "song.mp3"])
        func binaryFiles(name: String) {
            #expect(!MacRawTextSupport.applies(toFileNamed: name))
        }
    }
#endif
