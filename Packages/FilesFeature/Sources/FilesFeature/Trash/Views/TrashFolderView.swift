import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// Inside a deleted folder: its entries, a way back up, and restore for chosen entries or the
/// whole folder. Used on iPhone, iPad and the Mac.
struct TrashFolderView: View {
    @Bindable var store: StoreOf<TrashFolderFeature>

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backgroundGradient()
        #if os(macOS)
            .safeAreaInset(edge: .top, spacing: .zero) { macHeader }
            .navigationBarBackButtonHidden()
        #else
            .navigationTitle(store.title)
            .toolbar { toolbar }
        #endif
            // Its own: the trash list's chrome above it would show or hide these circles with the list's.
            .selectModeChrome(isSelecting: store.isSelecting)
            .task { store.send(.task) }
            .modifier(TrashRestorePrompts(
                store: store.scope(state: \.restore, action: \.restore),
                screenNotice: store.notice
            ))
            .sheet(isPresented: textBinding) {
                TrashTextSheet(state: store.text) { store.send(.textDismissed) }
            }
    }

    private var content: some View {
        TrashPhaseContent(phase: store.phase, isEmpty: store.entries.isEmpty, onRetry: { store.send(.retryTapped) }) {
            EmptyStateView(icon: IconKit.folder, message: L10n.Trash.folderEmpty)
        } loaded: {
            let entries = store.entries
            DSGroupedList {
                ForEach(entries) { entry in
                    row(entry, isFirst: entry.id == entries.first?.id, isLast: entry.id == entries.last?.id)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ entry: TrashEntry, isFirst: Bool, isLast: Bool) -> some View {
        SelectableListRow(
            selectionID: entry.id,
            isSelecting: store.isSelecting,
            isSelected: store.selectedNames.contains(entry.id),
            isFirst: isFirst,
            isLast: isLast,
            onTap: { store.send(.entryTapped(entry)) }
        ) {
            FileRowView(
                name: entry.name,
                isDirectory: entry.isDirectory,
                subtitle: entry.shareCount > 0 ? L10n.Trash.sharesBadge : nil,
                kind: TrashRowText.kind(entry.name, isDirectory: entry.isDirectory),
                dateModified: entry.modifiedAt,
                size: entry.size
            )
        } trailingSwipe: {
            if !store.isSelecting {
                Button { store.send(.restoreTapped([entry])) } label: {
                    IconKit.restore
                }
                .tint(.accent)
                .accessibilityLabel(L10n.Trash.restore)
            }
        } contextMenu: {
            if !store.isSelecting {
                Button { store.send(.restoreTapped([entry])) } label: {
                    Label { Text(L10n.Trash.restore) } icon: { IconKit.restore }
                }
                Button { store.send(.restoreToTapped([entry])) } label: {
                    Label { Text(L10n.Trash.restoreTo) } icon: { IconKit.restoreTo }
                }
            }
        }
        .disabled(store.restore.isRestoring)
        .accessibilityAction(named: L10n.Trash.restore) { store.send(.restoreTapped([entry])) }
    }

    #if os(macOS)
        private var macHeader: some View {
            MacPaneHeader(title: store.title, inset: MacPaneInset.sectionHeader, bottom: MacPaneInset.listGap) {
                if store.isSelecting {
                    Button(L10n.Trash.restoreTo) { store.send(.restoreToTapped(store.selectedEntries)) }
                        .buttonStyle(.macDS(.secondary))
                        .disabled(store.selectedNames.isEmpty || store.restore.isRestoring)
                    Button(L10n.Trash.restore) { store.send(.restoreTapped(store.selectedEntries)) }
                        .buttonStyle(.macDS(.secondary))
                        .disabled(store.selectedNames.isEmpty || store.restore.isRestoring)
                } else {
                    Button(L10n.Trash.restoreFolder) { store.send(.restoreFolderTapped) }
                        .buttonStyle(.macDS(.secondary))
                        .disabled(store.restore.isRestoring)
                }
                Button(store.isSelecting ? L10n.Common.done : L10n.Common.select) {
                    store.send(.selectModeToggled)
                }
                .buttonStyle(.macDS(.secondary))
                .disabled(store.entries.isEmpty || store.restore.isRestoring)
            }
        }
    #endif

    #if os(iOS)
        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            if store.canGoUp {
                ToolbarItem(placement: .navigation) {
                    Button { store.send(.upTapped) } label: {
                        Label { Text(L10n.Common.back) } icon: { IconKit.levelUp }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(store.isSelecting ? L10n.Common.done : L10n.Common.select) {
                        store.send(.selectModeToggled)
                    }
                    .disabled(store.entries.isEmpty)
                    Button { store.send(.restoreFolderTapped) } label: {
                        Label { Text(L10n.Trash.restoreFolder) } icon: { IconKit.restore }
                    }
                } label: {
                    IconKit.moreOptions
                }
                .accessibilityLabel(L10n.Common.edit)
                .disabled(store.restore.isRestoring)
            }
            if store.isSelecting {
                TrashSelectionToolbar(
                    isDisabled: store.selectedNames.isEmpty || store.restore.isRestoring,
                    onRestore: { store.send(.restoreTapped(store.selectedEntries)) },
                    onRestoreTo: { store.send(.restoreToTapped(store.selectedEntries)) },
                    onDelete: nil
                )
            }
        }
    #endif

    private var textBinding: Binding<Bool> {
        Binding(get: { store.text.isPresented }, set: {
            if !$0 {
                store.send(.textDismissed)
            }
        })
    }
}

#Preview("Entries") {
    NavigationStack { TrashFolderView(store: TrashPreviewData.folder()) }
}

#Preview("Entries, dark, large type") {
    NavigationStack { TrashFolderView(store: TrashPreviewData.folder()) }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Subfolder, selecting") {
    NavigationStack {
        TrashFolderView(store: TrashPreviewData.folder {
            $0.path = "Summer"
            $0.isSelecting = true
            $0.selectedNames = ["beach.jpg"]
        })
    }
}

#Preview("Empty folder") {
    NavigationStack { TrashFolderView(store: TrashPreviewData.folder { $0.entries = [] }) }
}

#Preview("Loading") {
    NavigationStack { TrashFolderView(store: TrashPreviewData.folder { $0.phase = .loading }) }
}

#Preview("Failed") {
    NavigationStack {
        TrashFolderView(store: TrashPreviewData.folder { $0.phase = .failed(L10n.Trash.folderLoadFailed) })
    }
}
