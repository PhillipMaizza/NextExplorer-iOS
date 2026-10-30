import CoreModels
@testable import FilesFeature
import Foundation
import Testing

struct FavoritesSortOptionTests {
    private func favorite(_ id: String, path: String, label: String? = nil) -> Favorite {
        Favorite(id: id, path: path, label: label, icon: "star", color: nil, position: 0, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))
    }

    private var favorites: [Favorite] {
        [
            favorite("1", path: "Work/Reports", label: "Zeta"),
            favorite("2", path: "Archive/Photos", label: "alpha"),
            favorite("3", path: "Music", label: "Beta 10"),
            favorite("4", path: "Docs", label: "Beta 9"),
        ]
    }

    @Test
    func manualKeepsTheOwnOrderAndReversesDescending() {
        #expect(FavoritesSortOption.manual.sorted(favorites, direction: .ascending).map(\.id) == ["1", "2", "3", "4"])
        #expect(FavoritesSortOption.manual.sorted(favorites, direction: .descending).map(\.id) == ["4", "3", "2", "1"])
    }

    @Test
    func nameSortsLikeFinderIgnoringCaseAndComparingNumbers() {
        #expect(FavoritesSortOption.name.sorted(favorites, direction: .ascending).map(\.id) == ["2", "4", "3", "1"])
        #expect(FavoritesSortOption.name.sorted(favorites, direction: .descending).map(\.id) == ["1", "3", "4", "2"])
    }

    @Test
    func locationSortsByPath() {
        #expect(FavoritesSortOption.location.sorted(favorites, direction: .ascending).map(\.id) == ["2", "4", "3", "1"])
    }
}
