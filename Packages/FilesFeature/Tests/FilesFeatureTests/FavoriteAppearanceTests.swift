import SwiftUI
import Testing

@testable import FilesFeature

@Suite
struct FavoriteAppearanceTests {
    @Test
    func hexStringParsesWithAndWithoutHash() {
        #expect(Color(hexString: "#009cff") != nil)
        #expect(Color(hexString: "009CFF") != nil)
        #expect(Color(hexString: "  #009cff  ") != nil)
    }

    @Test
    func hexStringRejectsMalformedValues() {
        #expect(Color(hexString: "") == nil)
        #expect(Color(hexString: "#fff") == nil)
        #expect(Color(hexString: "not-a-color") == nil)
        #expect(Color(hexString: "#gggggg") == nil)
    }

    @Test
    func favoriteColorResolvesPaletteEntriesAndArbitraryHex() {
        #expect(FavoriteColor.resolve(nil) == nil)
        #expect(FavoriteColor.resolve("") == nil)
        #expect(FavoriteColor.resolve("#009CFF") != nil) // palette, case-insensitive
        #expect(FavoriteColor.resolve("#123456") != nil) // off-palette but valid
        #expect(FavoriteColor.resolve("bogus") == nil)
    }

    @Test
    func swatchRingContrastsWithTheFill() {
        // Light fills → black ring, dark fills → white ring.
        let byHex = Dictionary(uniqueKeysWithValues: FavoriteColor.palette.map { ($0.hex, $0.ring) })
        #expect(byHex["#ffde00"] == .black) // bright yellow
        #expect(byHex["#ffb000"] == .black) // orange
        #expect(byHex["#009cff"] == .white) // blue
        #expect(byHex["#d873fb"] == .black) // light purple
    }

    @Test
    func favoriteColorMatchesIsCaseInsensitiveAndOptionalAware() {
        #expect(FavoriteColor.matches(nil, nil))
        #expect(FavoriteColor.matches("#FF5E5A", "#ff5e5a"))
        #expect(!FavoriteColor.matches(nil, "#ff5e5a"))
        #expect(!FavoriteColor.matches("#ff5e5a", nil))
    }

    @Test
    func favoriteIconMapsHeroiconTokensToSymbolsAndParsesWeight() {
        #expect(FavoriteIcon.bareName("outline:StarIcon") == "StarIcon")
        #expect(FavoriteIcon.bareName("BriefcaseIcon") == "BriefcaseIcon")
        #expect(FavoriteIcon.bareName(nil) == nil)
        #expect(FavoriteIcon.isFilled("solid:StarIcon"))
        #expect(!FavoriteIcon.isFilled("outline:StarIcon"))
        #expect(!FavoriteIcon.isFilled("StarIcon"))
        #expect(FavoriteIcon.token(name: "StarIcon", filled: true) == "solid:StarIcon")
        #expect(FavoriteIcon.symbolName(for: "outline:FolderIcon") == "folder")
        #expect(FavoriteIcon.symbolName(for: "Unknown") == "star") // fallback
    }
}
