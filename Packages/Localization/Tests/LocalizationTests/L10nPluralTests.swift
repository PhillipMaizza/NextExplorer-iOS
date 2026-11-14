import Foundation
@testable import Localization
import Testing

/// Every lookup is scoped to its own task with `withLanguage`, so these run in parallel with
/// anything else that reads strings.
@Suite("Plural strings")
struct L10nPluralTests {
    private func en(_ text: () -> String) -> String {
        LocalizationOverride.withLanguage("en", operation: text)
    }

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

    @Test("Transfer, favorites and upload counts say one item, not one items")
    func englishCounts() {
        #expect(en { L10n.Browse.transferMoved(1) } == "Moved 1 item")
        #expect(en { L10n.Browse.transferMoved(2) } == "Moved 2 items")
        #expect(en { L10n.Browse.transferMoved(0) } == "Moved 0 items")
        #expect(en { L10n.Browse.transferCopied(1) } == "Copied 1 item")
        #expect(en { L10n.Browse.transferCopied(4) } == "Copied 4 items")
        #expect(en { L10n.Favorites.removeConfirm(1) } == "Remove 1 Favorite?")
        #expect(en { L10n.Favorites.removeConfirm(3) } == "Remove 3 Favorites?")
        #expect(en { L10n.Uploads.stagingSkipped(1) } == "1 item couldn't be prepared and was left out.")
        #expect(en { L10n.Uploads.stagingSkipped(2) } == "2 items couldn't be prepared and were left out.")
        #expect(en { L10n.Uploads.notifyBody(1) } == "1 file uploaded")
        #expect(en { L10n.Uploads.notifyBody(9) } == "9 files uploaded")
    }

    @Test("A move with skips picks its form from the moved count, not the skipped one")
    func pluralFollowsTheMovedCount() {
        #expect(en { L10n.Browse.transferMovedWithSkipped(1, 5) } == "Moved 1 item, skipped 5")
        #expect(en { L10n.Browse.transferMovedWithSkipped(5, 1) } == "Moved 5 items, skipped 1")
        #expect(en { L10n.Browse.transferCopiedWithSkipped(1, 2) } == "Copied 1 item, skipped 2")
        #expect(en { L10n.Browse.transferCopiedWithSkipped(3, 1) } == "Copied 3 items, skipped 1")
    }

    @Test("Moved counts follow Polish, Romanian and Arabic forms")
    func movedInOtherLanguages() {
        func moved(_ language: String, _ count: Int) -> String {
            LocalizationOverride.withLanguage(language) { L10n.Browse.transferMoved(count) }
        }
        #expect(moved("pl", 1) == "Przeniesiono 1 element")
        #expect(moved("pl", 3) == "Przeniesiono 3 elementy")
        #expect(moved("pl", 12) == "Przeniesiono 12 elementów")
        #expect(moved("ro", 1) == "1 element mutat")
        #expect(moved("ro", 5) == "5 elemente mutate")
        #expect(moved("ro", 20) == "20 de elemente mutate")
        #expect(moved("ar", 2) == "تم نقل 2 عنصرين")
        #expect(moved("ar", 3) == "تم نقل 3 عناصر")
        #expect(moved("ar", 11) == "تم نقل 11 عنصرًا")
    }

    @Test("A language whose wording fits every count keeps it as its one form")
    func countNeutralWordingStays() {
        for count in [1, 5] {
            let czech = LocalizationOverride.withLanguage("cs") { L10n.Browse.transferMoved(count) }
            #expect(czech == "Přesunuto položek: \(count)")
        }
    }

    @Test("A scoped language does not leak into other work on the same process")
    func scopeStaysLocal() {
        let before = L10n.Common.cancel
        let scoped = LocalizationOverride.withLanguage("de") { L10n.Common.cancel }
        #expect(scoped == "Abbrechen")
        #expect(L10n.Common.cancel == before)
    }
}
