#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    /// The top of a Mac folder browsing sheet: a back button, the title with the current path
    /// under it, and optional trailing controls such as a search field.
    struct MacSheetHeader<Trailing: View>: View {
        let title: String
        var subtitle: String?
        let canGoBack: Bool
        var backLabel = L10n.Common.back
        let onBack: () -> Void
        @ViewBuilder var trailing: () -> Trailing

        var body: some View {
            HStack(spacing: .space8) {
                Button(action: onBack) { IconKit.back }
                    .disabled(!canGoBack)
                    .accessibilityLabelWithTooltip(backLabel)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.headline).lineLimit(1).truncationMode(.head)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer()
                trailing()
            }
        }
    }

    extension MacSheetHeader where Trailing == EmptyView {
        init(title: String, subtitle: String? = nil, canGoBack: Bool, backLabel: String = L10n.Common.back, onBack: @escaping () -> Void) {
            self.init(title: title, subtitle: subtitle, canGoBack: canGoBack, backLabel: backLabel, onBack: onBack) { EmptyView() }
        }
    }

    /// The trailing buttons of a Mac dialog: an optional spinner and extra button, Cancel (Esc)
    /// and the confirm button (Return), with any leading content such as a size estimate.
    struct MacDialogButtons<Leading: View>: View {
        let confirmTitle: String
        var isConfirmEnabled = true
        var isWorking = false
        /// `nil` hides Cancel, for a dialog whose only way out is its confirm button.
        var cancelTitle: String? = L10n.Common.cancel
        var secondaryTitle: String?
        var onSecondary: () -> Void = {}
        let onCancel: () -> Void
        let onConfirm: () -> Void
        @ViewBuilder var leading: () -> Leading

        var body: some View {
            HStack(spacing: .space8) {
                leading()
                Spacer()
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                if let secondaryTitle {
                    Button(secondaryTitle, action: onSecondary)
                }
                if let cancelTitle {
                    Button(cancelTitle, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isConfirmEnabled || isWorking)
            }
        }
    }

    extension MacDialogButtons where Leading == EmptyView {
        init(
            confirmTitle: String,
            isConfirmEnabled: Bool = true,
            isWorking: Bool = false,
            cancelTitle: String? = L10n.Common.cancel,
            secondaryTitle: String? = nil,
            onSecondary: @escaping () -> Void = {},
            onCancel: @escaping () -> Void,
            onConfirm: @escaping () -> Void
        ) {
            self.init(
                confirmTitle: confirmTitle,
                isConfirmEnabled: isConfirmEnabled,
                isWorking: isWorking,
                cancelTitle: cancelTitle,
                secondaryTitle: secondaryTitle,
                onSecondary: onSecondary,
                onCancel: onCancel,
                onConfirm: onConfirm
            ) { EmptyView() }
        }
    }

    /// A file or folder name with its icon, for Mac tables and lists: the accent folder or the
    /// secondary document glyph, and an optional path under the name.
    struct MacItemLabel: View {
        let name: String
        var subtitle: String?
        let isDirectory: Bool

        var body: some View {
            Label {
                VStack(alignment: .leading) {
                    Text(name).lineLimit(1).truncationMode(.middle)
                    if let subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                }
            } icon: {
                (isDirectory ? IconKit.folderFill : IconKit.document)
                    .foregroundStyle(isDirectory ? Color.accent : Color.secondary)
            }
        }
    }

    #Preview("Header") {
        VStack(spacing: .space16) {
            MacSheetHeader(title: "Move “report.pdf”", subtitle: "Documents/Reports", canGoBack: true, onBack: {}) {
                TextField("Search", text: .constant("")).textFieldStyle(.roundedBorder)
            }
            MacSheetHeader(title: "Choose Items", canGoBack: false, onBack: {})
        }
        .padding(.space16)
        .previewCanvasWidth(.sheet)
    }

    #Preview("Buttons") {
        VStack(spacing: .space16) {
            MacDialogButtons(confirmTitle: "Move", onCancel: {}, onConfirm: {})
            MacDialogButtons(confirmTitle: "Save", isWorking: true, onCancel: {}, onConfirm: {})
            MacDialogButtons(confirmTitle: "Download", isConfirmEnabled: false, onCancel: {}, onConfirm: {}) {
                Text(verbatim: "Estimated size: 45 MB").monospacedDigit()
            }
        }
        .padding(.space16)
        .previewCanvasWidth(.sheet)
    }

    #Preview("Item labels") {
        List {
            MacItemLabel(name: "Projects", isDirectory: true)
            MacItemLabel(name: "Reports", subtitle: "Documents/Work", isDirectory: true)
            MacItemLabel(name: "notes.txt", isDirectory: false)
        }
        .previewCanvas(.control)
    }
#endif
