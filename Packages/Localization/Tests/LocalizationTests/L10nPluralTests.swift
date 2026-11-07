import Foundation
@testable import Localization
import Testing

@Suite("Plural strings", .serialized)
struct L10nPluralTests {
    private func withLanguage<T>(_ language: String?, _ body: () -> T) -> T {
        LocalizationOverride.apply(language)
        defer { LocalizationOverride.apply(nil) }
        return body()
    }

    @Test("English picks the one and other forms")
    func english() {
        let one = withLanguage("en") { L10n.ShareUpload.notificationDoneBody(1, "Photos") }
        let many = withLanguage("en") { L10n.ShareUpload.notificationDoneBody(3, "Photos") }
        #expect(one == "1 file uploaded to “Photos”.")
        #expect(many == "3 files uploaded to “Photos”.")
    }

    @Test("Russian has four forms")
    func russian() {
        func text(_ count: Int) -> String {
            withLanguage("ru") { L10n.ShareUpload.failureOther(count) }
        }
        #expect(text(1) == "1 файл не удалось загрузить.")
        #expect(text(3) == "3 файла не удалось загрузить.")
        #expect(text(5) == "5 файлов не удалось загрузить.")
        #expect(text(21) == "21 файл не удалось загрузить.")
    }

    @Test("Arabic has six forms and Japanese only one")
    func arabicAndJapanese() {
        func arabic(_ count: Int) -> String {
            withLanguage("ar") { L10n.ShareUpload.failureOther(count) }
        }
        #expect(arabic(0).contains("ملف"))
        #expect(arabic(2).contains("ملفين"))
        #expect(arabic(3).contains("ملفات"))
        #expect(arabic(11).contains("ملفًا"))
        #expect(withLanguage("ja") { L10n.ShareUpload.failureOther(7) } == "7 個のファイルをアップロードできませんでした。")
    }
}
