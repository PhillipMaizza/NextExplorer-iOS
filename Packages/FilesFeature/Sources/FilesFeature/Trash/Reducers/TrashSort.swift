import CoreModels
import DesignSystem
import Foundation
import Localization
import SwiftUI

/// What the trash list orders by: the Browse fields a deleted item has, with the time it was
/// deleted in place of the time it was modified.
public enum TrashSortOption: String, Hashable, Sendable, CaseIterable {
    case name, size, deletedOn

    var title: String {
        switch self {
        case .name: L10n.Sort.name
        case .size: L10n.Sort.size
        case .deletedOn: L10n.Trash.columnDeletedOn
        }
    }

    var icon: Image {
        switch self {
        case .name: IconKit.textformat
        case .size: IconKit.size
        case .deletedOn: IconKit.calendar
        }
    }
}

extension TrashItem {
    /// The size and deletion time as the sort reads them, an unknown one first in ascending order.
    var sortSize: Int64 {
        size ?? 0
    }

    var sortDeletedAt: Date {
        deletedAt ?? .distantPast
    }
}

extension [TrashItem] {
    /// Ordered by `option` in `direction`; items that tie keep a stable order by name.
    func sorted(by option: TrashSortOption, _ direction: BrowseFeature.SortDirection) -> [TrashItem] {
        sorted { lhs, rhs in
            let order: ComparisonResult = switch option {
            case .name: .orderedSame
            case .size: Self.compare(lhs.sortSize, rhs.sortSize)
            case .deletedOn: Self.compare(lhs.sortDeletedAt, rhs.sortDeletedAt)
            }
            let resolved = order == .orderedSame ? lhs.name.localizedStandardCompare(rhs.name) : order
            return direction == .ascending ? resolved == .orderedAscending : resolved == .orderedDescending
        }
    }

    private static func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : lhs > rhs ? .orderedDescending : .orderedSame
    }
}
