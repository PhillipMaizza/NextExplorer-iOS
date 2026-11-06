@testable import CoreModels
import Foundation
import Testing

@Suite("EditableTextFiles")
struct EditableTextFilesTests {
    @Test("Text and code files are editable, whatever the case")
    func editable() {
        for name in ["notes.txt", "README.md", "app.js", "config.YAML", "script.sh", ".env", "styles.scss"] {
            #expect(EditableTextFiles.isEditable(name: name), "\(name)")
        }
    }

    @Test("Images, office files, archives and names without an extension are not")
    func notEditable() {
        for name in ["photo.jpg", "report.docx", "backup.zip", "Makefile", "notes.", "movie.mp4"] {
            #expect(!EditableTextFiles.isEditable(name: name), "\(name)")
        }
    }

    @Test("The server can add file types of its own")
    func serverExtensions() {
        #expect(!EditableTextFiles.isEditable(name: "query.sql"))
        #expect(EditableTextFiles.isEditable(name: "query.sql", serverExtensions: ["sql"]))
    }

    @Test("ServerFeatures reads the editor's extra file types, lowercased")
    func decodesEditorExtensions() throws {
        let json = Data(#"{"editor":{"extensions":["SQL","toml"],"maxFileSizeBytes":1048576}}"#.utf8)
        let features = try JSONDecoder().decode(ServerFeatures.self, from: json)
        #expect(features.editorExtensions == ["sql", "toml"])
        let none = try JSONDecoder().decode(ServerFeatures.self, from: Data("{}".utf8))
        #expect(none.editorExtensions.isEmpty)
    }
}
