@testable import FilesFeature
import SwiftUI
import Testing

struct GridTileOutlineTests {
    private typealias Tile = FileGridTile<EmptyView>

    private static let darkPage = Color.Resolved(red: 0.11, green: 0.11, blue: 0.12)
    private static let lightPage = Color.Resolved(red: 0.96, green: 0.96, blue: 0.95)

    @Test
    func aDarkSurfaceStandsOutOnADarkPage() {
        let surface = Color.Resolved(red: 0.17, green: 0.17, blue: 0.17)
        #expect(!Tile.isLowContrast(surface, Self.darkPage))
    }

    @Test
    func aWhiteWellMeltsIntoALightPage() {
        #expect(Tile.isLowContrast(Color.Resolved(red: 1, green: 1, blue: 1), Self.lightPage))
    }
}
