@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("Favorite")
struct FavoriteTests {
    private func makeFavorite(path: String, label: String?) -> Favorite {
        Favorite(
            id: "1",
            path: path,
            label: label,
            icon: "folder",
            color: nil,
            position: 0,
            createdAt: MockDate.date,
            updatedAt: MockDate.date
        )
    }

    @Test("happy path: displayName uses the custom label when present")
    func displayNameUsesLabel() {
        let favorite = makeFavorite(path: TestPath.homeDocs, label: "My Documents")
        #expect(favorite.displayName == "My Documents")
    }

    @Test("edge case: no label falls back to the last path component")
    func displayNameFallsBackToLastPathComponent() {
        let favorite = makeFavorite(path: "Home/Docs/Reports", label: nil)
        #expect(favorite.displayName == "Reports")
    }

    @Test("edge case: no label and no slash in path falls back to the whole path")
    func displayNameFallsBackToWholePathWhenNoSlash() {
        let favorite = makeFavorite(path: "RootVolume", label: nil)
        #expect(favorite.displayName == "RootVolume")
    }

    @Test("decodes a full favorites row")
    func decodesFullRow() throws {
        let favorite = try CoreModelsFixture.favoriteFullRow.decode(Favorite.self)
        #expect(favorite.label == TestFolder.docs)
        #expect(favorite.color == "#FF0000")
        #expect(favorite.position == 2)
    }
}
