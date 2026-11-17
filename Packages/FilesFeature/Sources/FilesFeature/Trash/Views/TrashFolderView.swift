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
            .background(Color.backgroundPrimary)
            .navigationTitle(store.title)
            .toolbar { toolbar }
            .toolbar { TrashRestoreCancelButton(store: store.scope(state: \.restore, action: \.restore)) }
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
            List {
                ForEach(store.entries) { entry in
                    row(entry)
                }
            }
            .listStyle(.plain)
        }
    }

    private func row(_ entry: TrashEntry) -> some View {
        Button { store.send(.entryTapped(entry)) } label: {
            HStack(spacing: .space12) {
                if store.isSelecting {
                    DSSelectionIndicator(isSelected: store.selectedNames.contains(entry.id))
                }
                FileRowView(
                    name: entry.name,
                    isDirectory: entry.isDirectory,
                    subtitle: entry.shareCount > 0 ? L10n.Trash.sharesBadge : nil,
                    kind: TrashRowText.kind(entry.name, isDirectory: entry.isDirectory),
                    dateModified: entry.modifiedAt,
                    size: entry.size
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(store.restore.isRestoring)
        .contextMenu {
            Button { store.send(.restoreTapped([entry])) } label: {
                Label { Text(L10n.Trash.restore) } icon: { IconKit.restore }
            }
            Button { store.send(.restoreToTapped([entry])) } label: {
                Label { Text(L10n.Trash.restoreTo) } icon: { IconKit.restoreTo }
            }
        }
        .accessibilityAction(named: L10n.Trash.restore) { store.send(.restoreTapped([entry])) }
    }

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
