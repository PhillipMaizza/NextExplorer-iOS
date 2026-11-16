#if os(iOS)
    import CoreModels
    import Localization
    import SwiftUI

    /// Offers the last file operation (a move, a copy, a rename, a new folder) to the system's undo:
    /// shake to undo, the three finger swipe and ⌘Z on a keyboard. Only the screen on show registers
    /// it, so a hidden tab or a folder under a pushed one never undoes from behind.
    struct FileUndoRegistration: ViewModifier {
        let undoStack: [FileUndoEntry]
        let undo: @MainActor @Sendable () -> Void

        @Environment(\.undoManager) private var undoManager
        @State private var target = UndoTarget()
        @State private var isOnScreen = false

        func body(content: Content) -> some View {
            content
                .onAppear {
                    isOnScreen = true
                    register()
                }
                .onDisappear {
                    isOnScreen = false
                    register()
                }
                .onChange(of: undoStack) { register() }
        }

        /// One registration at a time, always the newest entry: the reducer's stack stays the
        /// record, the system's undo only ever points at its top.
        private func register() {
            guard let undoManager else { return }
            undoManager.removeAllActions(withTarget: target)
            guard isOnScreen, let entry = undoStack.last else { return }
            let undo = undo
            undoManager.registerUndo(withTarget: target) { _ in
                MainActor.assumeIsolated {
                    undo()
                    // An undo refused while another file action runs leaves the stack as it was,
                    // so nothing else would offer it again. Registered after this undo has ended,
                    // so it lands as an undo, not a redo.
                    Task { @MainActor in register() }
                }
            }
            undoManager.setActionName(Self.actionName(entry))
        }

        /// The name the system shows after "Undo"; created items cover copies and new folders
        /// alike, so they read as a plain Undo.
        private static func actionName(_ entry: FileUndoEntry) -> String {
            switch entry.kind {
            case .moved: L10n.Browse.actionMove
            case .renamed: L10n.Browse.actionRename
            case .created, .madeNew: ""
            }
        }
    }

    /// The owner of the registered undo, so only this screen's registration is ever removed.
    final class UndoTarget: Sendable {}

    extension View {
        /// Offers the newest entry of `undoStack` to the system's undo while this screen is on show.
        func fileUndoRegistration(
            _ undoStack: [FileUndoEntry],
            undo: @escaping @MainActor @Sendable () -> Void
        ) -> some View {
            modifier(FileUndoRegistration(undoStack: undoStack, undo: undo))
        }
    }
#endif
