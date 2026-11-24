#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// The name cell while renaming: Return or clicking away commits, Esc cancels. An unchanged
    /// or empty name cancels; an invalid one goes on so the screen can say why it was refused.
    struct MacInlineRenameField: View {
        let originalName: String
        let isDirectory: Bool
        let onCommit: (String) -> Void
        let onCancel: () -> Void

        @State private var name: String
        @State private var selection: TextSelection?
        @State private var isFinished = false
        @State private var appearedAt = Date()
        @FocusState private var isFocused: Bool

        /// Right after the context menu closes, focus bounces back to the table once; a loss
        /// this early takes focus back instead of ending the rename.
        static let focusSettleInterval: TimeInterval = 0.6

        init(
            originalName: String,
            isDirectory: Bool,
            onCommit: @escaping (String) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.originalName = originalName
            self.isDirectory = isDirectory
            self.onCommit = onCommit
            self.onCancel = onCancel
            _name = State(initialValue: originalName)
        }

        var body: some View {
            TextField(L10n.Browse.renameNamePlaceholder, text: $name, selection: $selection)
                .labelsHidden()
                .textFieldStyle(.plain)
                .padding(.horizontal, .space8)
                .macFieldChrome(isFocused: isFocused, size: .compact)
                .focused($isFocused)
                .onAppear {
                    appearedAt = Date()
                    isFocused = true
                    // Started by Return, the table takes focus back once it finishes handling
                    // the key; asking again on the next turn of the run loop lands after that.
                    DispatchQueue.main.async { isFocused = true }
                }
                .onSubmit { finish(commit: true) }
                .onExitCommand { finish(commit: false) }
                .onChange(of: isFocused) { _, focused in
                    guard !focused else {
                        DispatchQueue.main.async { selection = TextSelection(range: stemRange) }
                        return
                    }
                    if Date().timeIntervalSince(appearedAt) < Self.focusSettleInterval {
                        isFocused = true
                    } else {
                        finish(commit: true)
                    }
                }
        }

        private var stemRange: Range<String.Index> {
            let stem = displayFileName(originalName, isDirectory: isDirectory, showExtension: false)
            let end = name.index(name.startIndex, offsetBy: stem.count, limitedBy: name.endIndex) ?? name.endIndex
            return name.startIndex ..< end
        }

        private func finish(commit: Bool) {
            guard !isFinished else { return }
            isFinished = true
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if commit, trimmed != originalName, !trimmed.isEmpty {
                onCommit(trimmed)
            } else {
                onCancel()
            }
        }
    }

    #Preview("Renaming") {
        MacInlineRenameField(originalName: "report.pdf", isDirectory: false, onCommit: { _ in }, onCancel: {})
            .padding(.space16)
            .previewCanvasWidth(.control)
    }
#endif
