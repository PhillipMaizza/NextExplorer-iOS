#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// The Mac Shared screen under the toolbar: the people strip, the outline table and the
    /// inspector beside the selected item. The inspector follows the selection: selecting one row
    /// shows it, deselecting (empty space, ⌘ click or Escape) hides it.
    struct MacSharedContent<Header: View>: View {
        let store: StoreOf<SharedFeature>
        let onToast: (DSToastMessage) -> Void
        @ViewBuilder let header: () -> Header

        @State private var selection: Set<MacSharedRow.ID> = []

        private var segment: SharedFeature.Segment {
            store.segment
        }

        private var isRailShown: Bool {
            store.state.phase(for: segment).hasLoaded && store.state.isFilterRowVisible(for: segment)
        }

        /// The selected item with every share on it, read live so edits and deletes show at once.
        /// Nil once the item is gone.
        private var inspectedItem: SharedFeature.Item? {
            guard selection.count == 1, let id = selection.first else {
                return nil
            }
            return store.state.item(for: SharedFeature.Detail(segment: segment, id: id.itemID))
        }

        private var selectedShareID: Share.ID? {
            guard selection.count == 1, case let .share(id, _) = selection.first else { return nil }
            return id
        }

        var body: some View {
            let item = inspectedItem
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    header()
                    if isRailShown {
                        SharedPeopleRail(
                            options: store.state.filterOptions(for: segment),
                            selection: store.state.filter(for: segment),
                            onSelect: { store.send(.filterChanged(segment, $0)) },
                            isCompact: true
                        )
                        .padding(.vertical, .space12)
                        Divider()
                    }
                    MacSharedTable(
                        store: store,
                        segment: segment,
                        selection: $selection,
                        onToast: onToast
                    )
                    .id(segment)
                }
                .frame(maxWidth: .infinity)
                .clipped()
                if let item {
                    MacSharedInspector(
                        store: store,
                        segment: segment,
                        item: item,
                        selectedShareID: selectedShareID,
                        onSelectShare: { selection = [.share($0, item: item.id)] },
                        onToast: onToast
                    )
                    .macInspectorColumn()
                }
            }
            .animation(DSMotion.stateFade, value: item == nil)
            .focusedSceneValue(\.closeMacInspector, item == nil ? nil : MacInspectorAction { selection = [] })
            .onChange(of: segment) { _, _ in selection = [] }
        }
    }

    /// A Shared store over the mock lists, for the Mac previews.
    @MainActor
    func macSharedPreview(
        _ segment: SharedFeature.Segment,
        mutate: (inout SharedFeature.State) -> Void = { _ in },
        @ViewBuilder content: (StoreOf<SharedFeature>) -> some View
    ) -> some View {
        content(sharedPreviewStore { state in
            state.segment = segment
            mutate(&state)
        })
        .backgroundGradient()
    }

    @MainActor
    private func contentPreview(
        _ segment: SharedFeature.Segment,
        mutate: (inout SharedFeature.State) -> Void = { _ in }
    ) -> some View {
        macSharedPreview(segment, mutate: mutate) { store in
            MacSharedContent(store: store, onToast: { _ in }) {
                MacPaneHeader(title: L10n.Shared.navigationTitle, inset: MacPaneInset.sectionHeader)
            }
        }
        .previewCanvas(.window)
    }

    #Preview("Content: by me") {
        contentPreview(.byMe)
    }

    #Preview("Content: by me, dark") {
        contentPreview(.byMe)
            .preferredColorScheme(.dark)
    }

    #Preview("Content: with me") {
        contentPreview(.withMe)
    }

    #Preview("Content: two people picked") {
        contentPreview(.byMe) { $0.filters[.byMe] = .people(["u2", "u6"]) }
    }
#endif
