import Foundation
@testable import Localization
import Testing

/// Every lookup is scoped to its own task with `withLanguage`, so these run in parallel with
/// anything else that reads strings.
@Suite("Plural strings")
struct L10nPluralTests {
    private func failureOther(_ language: String, _ count: Int) -> String {
        LocalizationOverride.withLanguage(language) { L10n.ShareUpload.failureOther(count) }
    }

    @Test("English picks the one and other forms")
    func english() {
        func body(_ count: Int) -> String {
            LocalizationOverride.withLanguage("en") { L10n.ShareUpload.notificationDoneBody(count, "Photos") }
        }
        #expect(body(1) == "1 file uploaded to “Photos”.")
        #expect(body(3) == "3 files uploaded to “Photos”.")
        #expect(body(0) == "0 files uploaded to “Photos”.")
    }

    @Test("Russian has four forms")
    func russian() {
        #expect(failureOther("ru", 1) == "1 файл не удалось загрузить.")
        #expect(failureOther("ru", 3) == "3 файла не удалось загрузить.")
        #expect(failureOther("ru", 5) == "5 файлов не удалось загрузить.")
        #expect(failureOther("ru", 21) == "21 файл не удалось загрузить.")
        #expect(failureOther("ru", 11) == "11 файлов не удалось загрузить.")
    }

    @Test("Arabic has its six forms, each with its own exact text")
    func arabic() {
        #expect(failureOther("ar", 0) == "تعذّر رفع 0 ملف.")
        #expect(failureOther("ar", 1) == "تعذّر رفع 1 ملف.")
        #expect(failureOther("ar", 2) == "تعذّر رفع 2 ملفين.")
        #expect(failureOther("ar", 3) == "تعذّر رفع 3 ملفات.")
        #expect(failureOther("ar", 11) == "تعذّر رفع 11 ملفًا.")
        #expect(failureOther("ar", 100) == "تعذّر رفع 100 ملف.")
    }

    @Test("Japanese has one form for every count")
    func japanese() {
        for count in [0, 1, 2, 7, 100] {
            #expect(failureOther("ja", count) == "\(count) 個のファイルをアップロードできませんでした。")
        }
    }

    @Test("Polish separates one, few and many, and 12 to 14 are many, not few")
    func polish() {
        #expect(failureOther("pl", 1) == "1 plik nie mógł zostać przesłany.")
        #expect(failureOther("pl", 2) == "2 pliki nie mogły zostać przesłane.")
        #expect(failureOther("pl", 5) == "5 plików nie mogło zostać przesłanych.")
        #expect(failureOther("pl", 22) == "22 pliki nie mogły zostać przesłane.")
        #expect(failureOther("pl", 12) == "12 plików nie mogło zostać przesłanych.")
        #expect(failureOther("pl", 0) == "0 plików nie mogło zostać przesłanych.")
    }

    @Test("Romanian has one, few (0 and 2 to 19) and other (20 and up)")
    func romanian() {
        #expect(failureOther("ro", 1) == "1 fișier nu a putut fi încărcat.")
        #expect(failureOther("ro", 0) == "0 fișiere nu au putut fi încărcate.")
        #expect(failureOther("ro", 2) == "2 fișiere nu au putut fi încărcate.")
        #expect(failureOther("ro", 19) == "19 fișiere nu au putut fi încărcate.")
        #expect(failureOther("ro", 20) == "20 de fișiere nu au putut fi încărcate.")
    }

    @Test("Hindi treats 0 and 1 as one, everything else as other")
    func hindi() {
        #expect(failureOther("hi", 0) == "0 फ़ाइल अपलोड नहीं की जा सकी।")
        #expect(failureOther("hi", 1) == "1 फ़ाइल अपलोड नहीं की जा सकी।")
        #expect(failureOther("hi", 2) == "2 फ़ाइलें अपलोड नहीं की जा सकीं।")
    }

    @Test("A scoped language does not leak into other work on the same process")
    func scopeStaysLocal() {
        let before = L10n.Common.cancel
        let scoped = LocalizationOverride.withLanguage("de") { L10n.Common.cancel }
        #expect(scoped == "Abbrechen")
        #expect(L10n.Common.cancel == before)
    }
}
