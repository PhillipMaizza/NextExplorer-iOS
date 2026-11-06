#if os(macOS)
    import Localization
    import SwiftUI

    public enum MacFormSheetMetrics {
        public static let width: CGFloat = 480
        static let padding: CGFloat = .space24
        static let spacing: CGFloat = .space16
        static let messageSpacing: CGFloat = .space8
    }

    private typealias Metrics = MacFormSheetMetrics

    /// A native Mac sheet around a form: its title, the labeled fields, any error, then Cancel
    /// (Esc) and the confirm button (Return) at the trailing edge.
    public struct MacFormSheet<Content: View>: View {
        let title: String
        /// Explanatory text under the title, across the full width of the sheet.
        var message: String?
        let confirmTitle: String
        var isConfirmEnabled = true
        var isWorking = false
        var errorMessage: String?
        /// `nil` hides Cancel, for a sheet whose only way out is its confirm button.
        var cancelTitle: String? = L10n.Common.cancel
        /// An extra button left of Cancel, such as "View in Shared".
        var secondaryTitle: String?
        var onSecondary: () -> Void = {}
        var width: CGFloat = Metrics.width
        let onCancel: () -> Void
        let onConfirm: () -> Void
        @ViewBuilder let content: () -> Content

        public init(
            title: String,
            message: String? = nil,
            confirmTitle: String,
            isConfirmEnabled: Bool = true,
            isWorking: Bool = false,
            errorMessage: String? = nil,
            cancelTitle: String? = L10n.Common.cancel,
            secondaryTitle: String? = nil,
            onSecondary: @escaping () -> Void = {},
            width: CGFloat = MacFormSheetMetrics.width,
            onCancel: @escaping () -> Void,
            onConfirm: @escaping () -> Void,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.title = title
            self.message = message
            self.confirmTitle = confirmTitle
            self.isConfirmEnabled = isConfirmEnabled
            self.isWorking = isWorking
            self.errorMessage = errorMessage
            self.cancelTitle = cancelTitle
            self.secondaryTitle = secondaryTitle
            self.onSecondary = onSecondary
            self.width = width
            self.onCancel = onCancel
            self.onConfirm = onConfirm
            self.content = content
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: Metrics.spacing) {
                VStack(alignment: .leading, spacing: Metrics.messageSpacing) {
                    Text(title).font(.headline)
                    if let message {
                        Text(message)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Form {
                    content()
                }
                .formStyle(.columns)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color.negativeText)
                }
                MacDialogButtons(
                    confirmTitle: confirmTitle,
                    isConfirmEnabled: isConfirmEnabled,
                    isWorking: isWorking,
                    cancelTitle: cancelTitle,
                    secondaryTitle: secondaryTitle,
                    onSecondary: onSecondary,
                    onCancel: onCancel,
                    onConfirm: onConfirm
                )
            }
            .padding(Metrics.padding)
            .frame(width: width)
        }
    }

    /// A field with its error underneath, for the rows of a `MacFormSheet`.
    public struct MacFieldError: View {
        let message: String?

        public init(message: String?) {
            self.message = message
        }

        public var body: some View {
            if let message {
                Text(message).font(.callout).foregroundStyle(Color.negativeText)
            }
        }
    }

    /// The trailing buttons of a Mac dialog: an optional spinner and extra button, Cancel (Esc)
    /// and the confirm button (Return), with any leading content such as a size estimate.
    public struct MacDialogButtons<Leading: View>: View {
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

        public init(
            confirmTitle: String,
            isConfirmEnabled: Bool = true,
            isWorking: Bool = false,
            cancelTitle: String? = L10n.Common.cancel,
            secondaryTitle: String? = nil,
            onSecondary: @escaping () -> Void = {},
            onCancel: @escaping () -> Void,
            onConfirm: @escaping () -> Void,
            @ViewBuilder leading: @escaping () -> Leading
        ) {
            self.confirmTitle = confirmTitle
            self.isConfirmEnabled = isConfirmEnabled
            self.isWorking = isWorking
            self.cancelTitle = cancelTitle
            self.secondaryTitle = secondaryTitle
            self.onSecondary = onSecondary
            self.onCancel = onCancel
            self.onConfirm = onConfirm
            self.leading = leading
        }

        public var body: some View {
            HStack(spacing: .space8) {
                leading()
                Spacer()
                if isWorking {
                    MacSpinner()
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

    public extension MacDialogButtons where Leading == EmptyView {
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

    /// The small native spinner Mac dialogs and panes show while they work, named for VoiceOver.
    public struct MacSpinner: View {
        public init() {}

        public var body: some View {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(L10n.Common.loading)
        }
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

    #Preview("Spinner") {
        MacSpinner()
            .padding(.space16)
    }

    #Preview("Form sheet") {
        MacFormSheet(title: "Create User", confirmTitle: "Create User", onCancel: {}, onConfirm: {}) {
            TextField("Email:", text: .constant(""))
            SecureField("Password:", text: .constant(""))
        }
    }
#endif
