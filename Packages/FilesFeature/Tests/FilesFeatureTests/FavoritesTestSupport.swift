import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@MainActor
protocol FavoritesTestSupport {
}

extension FavoritesTestSupport {
    var serverURL: URL { URL(fileURLWithPath: "/") }

    func makeFavorite(id: String = "1", path: String = TestFolder.documents, label: String? = nil, position: Int = 0) -> Favorite {
        Favorite(id: id, path: path, label: label, icon: "folder", color: nil, position: position, createdAt: MockDate.date, updatedAt: MockDate.date)
    }
}
