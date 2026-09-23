#if os(macOS)
    import DesignSystem
    import SwiftUI

    /// The Mac grouped list is not a `List`, so `onMove` never fires there. Each row instead
    /// drags its favorite id and accepts drops, translated into the same `IndexSet` and
    /// destination `onMove` would report, so the reducer handles both platforms identically.
    struct MacFavoriteReorder: ViewModifier {
        let favoriteID: String
        let orderedIDs: [String]
        let isEnabled: Bool
        let onMove: (IndexSet, Int) -> Void

        @State private var isTargeted = false

        func body(content: Content) -> some View {
            if isEnabled {
                content
                    .draggable(favoriteID)
                    .dropDestination(for: String.self) { droppedIDs, _ in
                        move(droppedIDs.first)
                    } isTargeted: { isTargeted = $0 }
                    .overlay {
                        if isTargeted {
                            RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                                .strokeBorder(Color.accent, lineWidth: Metrics.indicatorWidth)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                content
            }
        }

        private func move(_ draggedID: String?) -> Bool {
            guard let draggedID,
                  draggedID != favoriteID,
                  let source = orderedIDs.firstIndex(of: draggedID),
                  let target = orderedIDs.firstIndex(of: favoriteID)
            else { return false }
            // `onMove` destinations index the list before removal, so moving down lands after
            // the target row.
            onMove(IndexSet(integer: source), source < target ? target + 1 : target)
            return true
        }
    }

    private enum Metrics {
        static let indicatorWidth: CGFloat = 2
    }
#endif
