import Testing
@testable import CoreModels

@Suite struct SafeFileNameTests {
    @Test func plainNamesPassThrough() {
        #expect(SafeFileName.component("photo.jpg") == "photo.jpg")
        #expect(SafeFileName.component("My Report (final).pdf") == "My Report (final).pdf")
        #expect(SafeFileName.component("archive.tar.gz") == "archive.tar.gz")
    }

    @Test func directoryPortionsAreStripped() {
        #expect(SafeFileName.component("../../x.jpg") == "x.jpg")
        #expect(SafeFileName.component("../../../../Library/Preferences/evil.plist") == "evil.plist")
        #expect(SafeFileName.component("a/b/c/d.txt") == "d.txt")
        #expect(SafeFileName.component("/etc/passwd") == "passwd")
    }

    @Test func windowsSeparatorsAreStripped() {
        #expect(SafeFileName.component("..\\..\\x.jpg") == "x.jpg")
        #expect(SafeFileName.component("C:\\Windows\\system32\\evil.dll") == "evil.dll")
    }

    @Test func degenerateInputsFallBack() {
        #expect(SafeFileName.component("") == "file")
        #expect(SafeFileName.component(".") == "file")
        #expect(SafeFileName.component("..") == "file")
        #expect(SafeFileName.component("/") == "file")
        #expect(SafeFileName.component("../..") == "file")
        #expect(SafeFileName.component("", fallback: "download") == "download")
    }

    @Test func isSafeComponentRejectsAnythingThatWouldBeRewritten() {
        #expect(SafeFileName.isSafeComponent("photo.jpg"))
        #expect(!SafeFileName.isSafeComponent("../photo.jpg"))
        #expect(!SafeFileName.isSafeComponent("sub/photo.jpg"))
        #expect(!SafeFileName.isSafeComponent(".."))
        #expect(!SafeFileName.isSafeComponent(""))
    }
}
