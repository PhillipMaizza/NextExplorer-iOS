import CoreModels
import Foundation
import Localization

/// How the Mac Favorites table orders its rows. `manual` keeps the person's own order, the only
/// one dragging rows can change; the others sort a copy for display.
enum FavoritesSortOption: String, CaseIterable, Hashable, Sendable {
    case manual, name, location

    var title: String {
        switch self {
        case .manual: L10n.Sort.manual
        case .name: L10n.Sort.name
        case .location: L10n.FileInfo.rowLocation
        }
    }

    func sorted(_ favorites: [Favorite], direction: BrowseFeature.SortDirection) -> [Favorite] {
        let ordered: [Favorite] = switch self {
        case .manual: favorites
        case .name: favorites.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .location: favorites.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
        return direction == .descending ? ordered.reversed() : ordered
    }
}
