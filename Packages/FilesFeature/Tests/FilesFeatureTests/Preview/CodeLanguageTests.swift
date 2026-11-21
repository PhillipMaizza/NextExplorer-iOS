@testable import FilesFeature
import Testing

struct CodeLanguageTests {
    private enum Kind {
        static let jsx = "jsx"
        static let upperCaseYAML = "YML"
        static let zsh = "zsh"
        static let cxx = "cxx"
        static let unknown = "dat"
    }

    @Test
    func aliasesReachTheirLanguageWhateverTheCase() {
        #expect(CodeLanguage(kind: Kind.jsx) == .javaScript)
        #expect(CodeLanguage(kind: Kind.upperCaseYAML) == .yaml)
        #expect(CodeLanguage(kind: Kind.zsh) == .bash)
        #expect(CodeLanguage(kind: Kind.cxx) == .cpp)
    }

    @Test
    func anUnknownKindStaysPlainText() {
        #expect(CodeLanguage(kind: Kind.unknown) == nil)
    }
}
