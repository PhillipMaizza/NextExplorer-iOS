#if os(macOS)
    import CoreModels
    import Foundation

    /// The Mac file table's column sort, as the Browse sort it stands for.
    extension BrowseFeature.SortOption {
        func tableComparator(_ direction: BrowseFeature.SortDirection) -> KeyPathComparator<FileItem> {
            let order: SortOrder = direction == .ascending ? .forward : .reverse
            return switch self {
            case .name: KeyPathComparator(\.name, order: order)
            case .dateModified: KeyPathComparator(\.dateModified, order: order)
            case .size: KeyPathComparator(\.size, order: order)
            case .kind: KeyPathComparator(\.kind, order: order)
            }
        }

        init(tableComparator: KeyPathComparator<FileItem>) {
            self = switch tableComparator.keyPath {
            case \FileItem.dateModified: .dateModified
            case \FileItem.size: .size
            case \FileItem.kind: .kind
            default: .name
            }
        }
    }
#endif
