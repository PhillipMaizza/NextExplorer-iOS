@testable import FilesFeature
import Localization
import Testing

@Suite("FileNameValidation")
struct FileNameValidationTests {
    @Test("edge case: a path separator is rejected before any network call")
    func separatorsRejected() {
        #expect(FileNameValidation.errorMessage(forTrimmed: "foo/bar") == L10n.Browse.nameErrorSeparators)
        #expect(FileNameValidation.errorMessage(forTrimmed: "foo\\bar") == L10n.Browse.nameErrorSeparators)
        #expect(!FileNameValidation.isAcceptable(trimmed: "a/b"))
    }

    @Test("edge case: the reserved . and .. names are rejected")
    func reservedRejected() {
        #expect(FileNameValidation.errorMessage(forTrimmed: ".") == L10n.Browse.nameErrorReserved)
        #expect(FileNameValidation.errorMessage(forTrimmed: "..") == L10n.Browse.nameErrorReserved)
        #expect(!FileNameValidation.isAcceptable(trimmed: ".."))
    }

    @Test("empty is not an error message (the disabled button expresses that), but is not acceptable")
    func emptyHasNoMessageButIsNotAcceptable() {
        #expect(FileNameValidation.errorMessage(forTrimmed: "") == nil)
        #expect(!FileNameValidation.isAcceptable(trimmed: ""))
    }

    @Test("ordinary names, including dotfiles and names with spaces or dots, pass")
    func ordinaryNamesPass() {
        for name in ["Reports", "vacation photos", "archive.2026", ".gitignore", "..leading", "a.b.c"] {
            #expect(FileNameValidation.isAcceptable(trimmed: name), "\(name) should be acceptable")
        }
    }

    @Test("monkey test: thousands of garbage names never crash, and any accepted name is genuinely safe")
    func fileNameFuzzing() {
        var rng = SplitMix64(seed: 0xF11E_0027)
        for _ in 0 ..< 4000 {
            let trimmed = FuzzStrings.random(using: &rng, maxLength: 40)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = FileNameValidation.errorMessage(forTrimmed: trimmed)
            // isAcceptable must agree with the message + empty rule, always.
            #expect(FileNameValidation.isAcceptable(trimmed: trimmed) == (!trimmed.isEmpty && message == nil))
            // A name we accept can never smuggle a separator or a reserved name past us.
            if FileNameValidation.isAcceptable(trimmed: trimmed) {
                #expect(!trimmed.contains("/") && !trimmed.contains("\\"))
                #expect(trimmed != "." && trimmed != "..")
            }
        }
    }
}
