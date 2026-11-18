@testable import FilesFeature
import SwiftUI
import Testing

struct GridTileOutlineTests {
    private typealias Tile = FileGridTile<EmptyView>

    private static let darkPage = Color.Resolved(red: 0.11, green: 0.11, blue: 0.12)
    private static let lightPage = Color.Resolved(red: 0.96, green: 0.96, blue: 0.95)

    @Test
    func aNearBlackTintMeltsIntoADarkPage() {
        let navy = Color.Resolved(red: 0.07, green: 0.09, blue: 0.15)
        let well = Tile.composite(navy, opacity: 0.22, over: Self.darkPage)
        #expect(Tile.isLowContrast(well, Self.darkPage))
    }

    @Test
    func aBrightTintStandsOutOnADarkPage() {
        let amber = Color.Resolved(red: 0.96, green: 0.62, blue: 0.04)
        let well = Tile.composite(amber, opacity: 0.22, over: Self.darkPage)
        #expect(!Tile.isLowContrast(well, Self.darkPage))
    }

    @Test
    func aWhiteWellMeltsIntoALightPage() {
        #expect(Tile.isLowContrast(Color.Resolved(red: 1, green: 1, blue: 1), Self.lightPage))
    }

    @Test
    func aFullyTransparentTintLeavesThePage() {
        let well = Tile.composite(Color.Resolved(red: 1, green: 0, blue: 0), opacity: 0, over: Self.darkPage)
        #expect(well.linearRed == Self.darkPage.linearRed)
    }
}
