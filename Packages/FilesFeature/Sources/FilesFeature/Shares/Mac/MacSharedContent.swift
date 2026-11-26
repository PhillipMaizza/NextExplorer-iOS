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
        @State private var isPeeking = false

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
                    isPeeking: $isPeeking,
                    onOpen: open,
                    onToast: onToast
                )
                .id(segment)
            }
            .macInspectorPane(isOpen: item != nil, onClose: { selection = [] }) {
                if let item {
                    MacSharedInspector(
                        store: store,
                        segment: segment,
                        item: item,
                        selectedShareID: selectedShareID,
                        onSelectShare: { selection = [.share($0, item: item.id)] },
                        onOpen: open,
                        onToast: onToast
                    )
                }
            }
            .onChange(of: segment) { _, _ in selection = [] }
        }

        private func open(_ share: Share) {
            if share.isDirectory {
                afterMouseUp {
                    selection = []
                    store.send(.openTapped(share))
                }
            } else if share.receivedFileItem != nil {
                isPeeking = true
            }
        }

        private func afterMouseUp(_ work: @escaping @MainActor () -> Void) {
            guard NSEvent.pressedMouseButtons != 0 else {
                DispatchQueue.main.async(execute: work)
                return
            }
            let monitor = MouseUpMonitor()
            monitor.token = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
                if let token = monitor.token {
                    NSEvent.removeMonitor(token)
                    monitor.token = nil
                    DispatchQueue.main.async(execute: work)
                }
                return event
            }
        }
    }

    private final class MouseUpMonitor {
        var token: Any?
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
