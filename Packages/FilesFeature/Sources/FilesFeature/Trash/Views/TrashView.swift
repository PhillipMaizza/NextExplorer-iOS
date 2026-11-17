import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    /// An item whose volume is gone reads as out of reach.
    static let unavailableOpacity: Double = 0.5
}

/// The trash on iPhone and iPad, pushed from the Browse root's Trash row.
struct TrashView: View {
    @Bindable var store: StoreOf<TrashFeature>
    @Dependency(\.date) private var date
    @Dependency(\.calendar) private var calendar

    var body: some View {
        content
            .background(Color.backgroundPrimary)
            .navigationTitle(L10n.Trash.title)
            .toolbar { toolbar }
            .toolbar { TrashRestoreCancelButton(store: store.scope(state: \.restore, action: \.restore)) }
            .task { store.send(.task) }
            .modifier(TrashRestorePrompts(
                store: store.scope(state: \.restore, action: \.restore),
                screenNotice: store.notice
            ))
            .dsAlert(isPresented: confirmationBinding) { confirmationAlert }
            .sheet(isPresented: textBinding) {
                TrashTextSheet(state: store.text) { store.send(.textDismissed) }
            }
            .navigationDestination(item: $store.scope(state: \.folder, action: \.folder)) { folderStore in
                TrashFolderView(store: folderStore)
            }
    }

    private var content: some View {
        TrashPhaseContent(phase: store.phase, isEmpty: store.items.isEmpty, onRetry: { store.send(.retryTapped) }) {
            VStack(spacing: .space24) {
                header
                EmptyStateView(icon: IconKit.delete, message: L10n.Trash.emptyState)
            }
            .padding(.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .refreshable { await store.send(.refreshPulled).finish() }
        } loaded: {
            List {
                Section {
                    ForEach(store.items) { item in
                        row(item)
                    }
                } header: {
                    header
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .refreshable { await store.send(.refreshPulled).finish() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: .space8) {
            if !store.isEnabled {
                DSInfoCard(L10n.Trash.disabledNotice)
            } else if let days = store.retentionDays {
                Text(L10n.Trash.subtitle(days))
                    .type(.body3(.regular), style: .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: TrashItem) -> some View {
        Button { store.send(.itemTapped(item)) } label: {
            HStack(spacing: .space12) {
                if store.isSelecting {
                    DSSelectionIndicator(isSelected: store.selectedIDs.contains(item.id))
                }
                FileRowView(
                    name: item.name,
                    isDirectory: item.isDirectory,
                    subtitle: TrashRowText.subtitle(item, now: date.now, calendar: calendar),
                    kind: TrashRowText.kind(item.name, isDirectory: item.isDirectory)
                )
            }
            .opacity(item.isAvailable ? 1 : Constants.unavailableOpacity)
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy)
        .contextMenu { TrashItemMenu(item: item, store: store) }
        .swipeActions(edge: .trailing) {
            if item.isAvailable {
                Button(role: .destructive) { store.send(.deletePermanentlyTapped([item])) } label: {
                    Label { Text(L10n.Trash.deletePermanently) } icon: { IconKit.delete }
                }
                Button { store.send(.restoreTapped([item])) } label: {
                    Label { Text(L10n.Trash.restore) } icon: { IconKit.restore }
                }
                .tint(.accent)
            }
        }
        .accessibilityAction(named: L10n.Trash.restore) { store.send(.restoreTapped([item])) }
        .accessibilityAction(named: L10n.Trash.deletePermanently) { store.send(.deletePermanentlyTapped([item])) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !store.items.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button(store.isSelecting ? L10n.Common.done : L10n.Common.select) {
                    store.send(.selectModeToggled)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) { store.send(.emptyTrashTapped) } label: {
                    Label { Text(L10n.Trash.emptyTrash) } icon: { IconKit.delete }
                }
                .disabled(store.isBusy)
            }
        }
        if store.isSelecting {
            TrashSelectionToolbar(
                isDisabled: store.selectedIDs.isEmpty || store.isBusy,
                onRestore: { store.send(.restoreTapped(store.selectedItems)) },
                onRestoreTo: { store.send(.restoreToTapped(store.selectedItems)) },
                onDelete: { store.send(.deletePermanentlyTapped(store.selectedItems)) }
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

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { store.confirmPhase != .idle }, set: { _ in })
    }

    private var confirmationAlert: DSAlertSheet {
        TrashConfirmation.alert(
            store.confirmation,
            isRunning: store.confirmPhase.isRunning,
            onConfirm: { store.send(.confirmationConfirmed) },
            onDismiss: { store.send(.confirmationDismissed) }
        )
    }
}

#Preview("Loaded") {
    NavigationStack { TrashView(store: TrashPreviewData.trash()) }
}

#Preview("Loaded, dark, large type") {
    NavigationStack { TrashView(store: TrashPreviewData.trash()) }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Selecting") {
    NavigationStack {
        TrashView(store: TrashPreviewData.trash {
            $0.isSelecting = true
            $0.selectedIDs = ["t1"]
        })
    }
}

#Preview("Switched off with leftovers") {
    NavigationStack { TrashView(store: TrashPreviewData.trash { $0.isEnabled = false }) }
}

#Preview("Empty") {
    NavigationStack { TrashView(store: TrashPreviewData.trash { $0.items = [] }) }
}

#Preview("Loading") {
    NavigationStack {
        TrashView(store: TrashPreviewData.trash {
            $0.items = []
            $0.phase = .loading
        })
    }
}

#Preview("Failed") {
    NavigationStack {
        TrashView(store: TrashPreviewData.trash {
            $0.items = []
            $0.phase = .failed(L10n.Trash.loadFailed)
        })
    }
}

#Preview("Empty Trash confirmation") {
    NavigationStack {
        TrashView(store: TrashPreviewData.trash {
            $0.confirmation = .empty
            $0.confirmPhase = .confirming
        })
    }
}
