import ComposableArchitecture
import CoreModels
import DesignSystem
import FolderPickerFeature
import Localization
import SwiftUI

/// What a restore asks and shows, on the trash list and inside a deleted folder alike: the share
/// link question, the folder picker for Restore To, its progress while it runs, and the result.
struct TrashRestorePrompts: ViewModifier {
    @Bindable var store: StoreOf<TrashRestoreFeature>
    /// The screen's own result, beside the restore's: one toast shows whichever changed last.
    let screenNotice: TrashNotice?
    @State private var toast: DSToastMessage?

    func body(content: Content) -> some View {
        content
            .dsAlert(isPresented: shareChoiceBinding) { shareChoiceAlert }
            .sheet(item: $store.scope(state: \.destinationPicker, action: \.destinationPicker)) { pickerStore in
                DestinationPickerView(store: pickerStore)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { folderProgressBar }
            .dsToast(progressBinding)
            .dsToast($toast)
            .onChange(of: store.notice) { _, notice in show(notice) }
            .onChange(of: screenNotice) { _, notice in show(notice) }
    }

    private func show(_ notice: TrashNotice?) {
        guard let notice else { return }
        if notice.isFailure {
            toast = .failure(notice.text)
        } else if notice.isUndoable {
            toast = .success(notice.text, actionTitle: L10n.Menu.undo) { store.send(.undoTapped) }
        } else {
            toast = .success(notice.text)
        }
    }

    private var shareChoiceBinding: Binding<Bool> {
        Binding(get: { store.awaitingShareChoice != nil }, set: { _ in })
    }

    private var shareChoiceAlert: DSAlertSheet {
        let request = store.awaitingShareChoice
        var lines = [L10n.Trash.sharesChooseMessage(request?.shareCount ?? 0)]
        if request?.destination != nil {
            lines.append(L10n.Trash.sharesChooseElsewhere)
        }
        return DSAlertSheet(
            icon: IconKit.shareLink,
            title: L10n.Trash.sharesChooseTitle,
            message: lines.joined(separator: "\n\n"),
            confirmTitle: L10n.Trash.sharesKeep,
            dismissTitle: L10n.Common.cancel,
            neutralTitle: L10n.Trash.sharesDrop,
            closeAccessibilityLabel: L10n.Common.close,
            onConfirm: { store.send(.shareChoiceMade(.restore)) },
            onNeutral: { store.send(.shareChoiceMade(.drop)) },
            onDismiss: { store.send(.shareChoiceDismissed) }
        )
    }

    /// Read only: the restore clears it when it ends. A quick restore in place only says it runs.
    private var progressBinding: Binding<DSToastMessage?> {
        Binding(get: { store.phase == .inPlace ? .progress(L10n.Trash.restoring) : nil }, set: { _ in })
    }

    /// A restore into a folder copies and can take a while: the transfer bar with how far it is and Cancel.
    @ViewBuilder
    private var folderProgressBar: some View {
        if case let .toFolder(progress) = store.phase {
            TransferProgressBar(
                icon: IconKit.restoreTo,
                title: L10n.Trash.restoring,
                progress: progress,
                cancelLabel: L10n.Common.cancel,
                onTap: {},
                onCancelAll: { store.send(.cancelTapped) }
            )
            .padding(.horizontal, .space16)
            .padding(.bottom, .space16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// A text file from the trash, read only.
struct TrashTextSheet: View {
    let state: TrashTextPreview.State
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case let .loaded(text):
                    CodeEditorView(
                        kind: TrashRowText.kind(text.name, isDirectory: false),
                        text: .constant(text.content),
                        isEditable: false
                    )
                case .loading, .closed:
                    DSSpinner()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.backgroundPrimary)
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Common.close, action: onClose)
                    }
                }
        }
    }

    private var title: String {
        switch state {
        case let .loaded(text): text.name
        case let .loading(name): name
        case .closed: ""
        }
    }
}

#Preview("Share link question") {
    Color.backgroundPrimary
        .modifier(TrashRestorePrompts(
            store: Store(initialState: {
                var state = TrashRestoreFeature.State(serverURL: TrashPreviewData.serverURL)
                state.awaitingShareChoice = .init(target: .items(["t1"]), destination: "Files", shareCount: 2)
                return state
            }()) { TrashRestoreFeature() },
            screenNotice: nil
        ))
}

#Preview("Restoring") {
    Color.backgroundPrimary
        .modifier(TrashRestorePrompts(
            store: Store(initialState: {
                var state = TrashRestoreFeature.State(serverURL: TrashPreviewData.serverURL)
                state.phase = .inPlace
                return state
            }()) { TrashRestoreFeature() },
            screenNotice: nil
        ))
}

#Preview("Restoring into a folder") {
    Color.backgroundPrimary
        .modifier(TrashRestorePrompts(
            store: Store(initialState: {
                var state = TrashRestoreFeature.State(serverURL: TrashPreviewData.serverURL)
                state.phase = .toFolder(progress: 0.4)
                return state
            }()) { TrashRestoreFeature() },
            screenNotice: nil
        ))
}

#Preview("Restoring into a folder, waiting, dark") {
    Color.backgroundPrimary
        .modifier(TrashRestorePrompts(
            store: Store(initialState: {
                var state = TrashRestoreFeature.State(serverURL: TrashPreviewData.serverURL)
                state.phase = .toFolder(progress: nil)
                return state
            }()) { TrashRestoreFeature() },
            screenNotice: nil
        ))
        .preferredColorScheme(.dark)
}

#Preview("Text file") {
    TrashTextSheet(state: .loaded(TrashText(name: "notes.md", content: "# Notes\nKept for later.")), onClose: {})
}

#Preview("Text file loading, dark") {
    TrashTextSheet(state: .loading(name: "notes.md"), onClose: {})
        .preferredColorScheme(.dark)
}
