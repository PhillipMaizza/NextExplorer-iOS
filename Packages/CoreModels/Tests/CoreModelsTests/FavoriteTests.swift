import Foundation
import Testing
@testable import CoreModels

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
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @Test("happy path: displayName uses the custom label when present")
    func displayNameUsesLabel() {
        let favorite = makeFavorite(path: "Home/Docs", label: "My Documents")
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
        let json = #"""
        {"id": "f1", "path": "Home/Docs", "label": "Docs", "icon": "folder", "color": "#FF0000", "position": 2, "createdAt": 1800000000, "updatedAt": 1800100000}
        """#
        let favorite = try JSONDecoder().decode(Favorite.self, from: Data(json.utf8))
        #expect(favorite.label == "Docs")
        #expect(favorite.color == "#FF0000")
        #expect(favorite.position == 2)
    }

    @Test("error path: missing required field fails to decode")
    func missingRequiredFieldThrows() {
        let json = #"{"id": "f1", "path": "Home"}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(Favorite.self, from: Data(json.utf8))
        }
    }
}
