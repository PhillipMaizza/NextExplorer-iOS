#if os(macOS)
    import CoreModels
    import Localization
    import SwiftUI

    /// The name cell while renaming: Return or clicking away commits, Esc cancels. An unchanged
    /// or invalid name cancels instead of asking the server.
    struct MacInlineRenameField: View {
        let originalName: String
        let onCommit: (String) -> Void
        let onCancel: () -> Void

        @State private var name: String
        @State private var isFinished = false
        @State private var appearedAt = Date()
        @FocusState private var isFocused: Bool

        /// Right after the context menu closes, focus bounces back to the table once; a loss
        /// this early takes focus back instead of ending the rename.
        private static let focusSettleInterval: TimeInterval = 0.6

        init(originalName: String, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.originalName = originalName
            self.onCommit = onCommit
            self.onCancel = onCancel
            _name = State(initialValue: originalName)
        }

        var body: some View {
            TextField(L10n.Browse.renameNamePlaceholder, text: $name)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear {
                    appearedAt = Date()
                    isFocused = true
                }
                .onSubmit { finish(commit: true) }
                .onExitCommand { finish(commit: false) }
                .onChange(of: isFocused) { _, focused in
                    guard !focused else { return }
                    if Date().timeIntervalSince(appearedAt) < Self.focusSettleInterval {
                        isFocused = true
                    } else {
                        finish(commit: true)
                    }
                }
        }

        private func finish(commit: Bool) {
            guard !isFinished else { return }
            isFinished = true
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if commit, trimmed != originalName, FileNameValidation.isAcceptable(trimmed: trimmed) {
                onCommit(trimmed)
            } else {
                onCancel()
            }
        }
    }

    #Preview("Renaming") {
        MacInlineRenameField(originalName: "report.pdf", onCommit: { _ in }, onCancel: {})
            .padding(.space16)
            .frame(width: 320)
    }
#endif
