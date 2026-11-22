#if os(macOS)
    @testable import FilesFeature
    import Localization
    import Testing

    @MainActor
    struct MacTipJarSheetTests {
        @Test
        func everyTierHasItsOwnNote() {
            #expect(MacTipJarSheet.note(for: TipProductID.coffee) == L10n.TipJar.noteCoffee)
            #expect(MacTipJarSheet.note(for: TipProductID.cake) == L10n.TipJar.noteCake)
            #expect(MacTipJarSheet.note(for: TipProductID.generous) == L10n.TipJar.noteGenerous)
            #expect(Set(TipProductID.all.map(MacTipJarSheet.note(for:))).count == TipProductID.all.count)
        }

        @Test
        func theFeaturedTierIsOneOfTheProducts() {
            #expect(TipProductID.all.contains(TipProductID.featured))
        }
    }
#endif
