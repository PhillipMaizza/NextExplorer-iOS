#if os(macOS)
    import Localization
    import SwiftUI

    public enum MacFormSheetMetrics {
        public static let width: CGFloat = 480
        static let padding: CGFloat = .space24
        public static let spacing: CGFloat = .space16
        static let messageSpacing: CGFloat = .space8
        static let successBadgeSize: CGFloat = .size32
    }

    private typealias Metrics = MacFormSheetMetrics

    public struct MacDialogHeading: View {
        let title: String
        let message: String?

        public init(title: String, message: String?) {
            self.title = title
            self.message = message
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: Metrics.messageSpacing) {
                Text(title).type(.headline4)
                if let message {
                    Text(message)
                        .type(.body2(.regular), style: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    public enum MacFormSheetLayout {
        case columns
        case stacked
    }

    /// A native Mac sheet around a form: its title, the labeled fields, any error, then Cancel
    /// (Esc) and the confirm button (Return) at the trailing edge.
    public struct MacFormSheet<Content: View, Below: View>: View {
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
        var destructiveTitle: String?
        var onDestructive: () -> Void = {}
        var width: CGFloat = Metrics.width
        var layout = MacFormSheetLayout.columns
        var isSuccess = false
        let onCancel: () -> Void
        let onConfirm: () -> Void
        @ViewBuilder let content: () -> Content
        @ViewBuilder let below: () -> Below

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
            destructiveTitle: String? = nil,
            onDestructive: @escaping () -> Void = {},
            width: CGFloat = MacFormSheetMetrics.width,
            layout: MacFormSheetLayout = .columns,
            isSuccess: Bool = false,
            onCancel: @escaping () -> Void,
            onConfirm: @escaping () -> Void,
            @ViewBuilder content: @escaping () -> Content,
            @ViewBuilder below: @escaping () -> Below
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
            self.destructiveTitle = destructiveTitle
            self.onDestructive = onDestructive
            self.width = width
            self.layout = layout
            self.isSuccess = isSuccess
            self.onCancel = onCancel
            self.onConfirm = onConfirm
            self.content = content
            self.below = below
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: Metrics.spacing) {
                HStack(spacing: .space12) {
                    if isSuccess {
                        IconKit.checkmark
                            .fontWeight(.bold)
                            .foregroundStyle(Color.white)
                            .frame(width: Metrics.successBadgeSize, height: Metrics.successBadgeSize)
                            .background(Circle().fill(Color.positive))
                            .macDialogPop()
                            .accessibilityHidden(true)
                    }
                    MacDialogHeading(title: title, message: message)
                }
                .animation(DSMotion.pop, value: isSuccess)
                switch layout {
                case .columns:
                    Form {
                        content()
                    }
                    .formStyle(.columns)
                case .stacked:
                    VStack(alignment: .leading, spacing: Metrics.spacing) {
                        content()
                    }
                    .toggleStyle(.macSwitch)
                }
                below()
                MacFieldError(message: errorMessage, textType: .body2(.regular))
                MacDialogButtons(
                    confirmTitle: confirmTitle,
                    isConfirmEnabled: isConfirmEnabled,
                    isWorking: isWorking,
                    cancelTitle: cancelTitle,
                    secondaryTitle: secondaryTitle,
                    onSecondary: onSecondary,
                    onCancel: onCancel,
                    onConfirm: onConfirm
                ) {
                    if let destructiveTitle {
                        Button(destructiveTitle, role: .destructive, action: onDestructive)
                            .buttonStyle(.macDS(.secondary))
                    }
                }
            }
            .padding(Metrics.padding)
            .frame(width: width)
        }
    }

    public extension MacFormSheet where Below == EmptyView {
        init(
            title: String,
            message: String? = nil,
            confirmTitle: String,
            isConfirmEnabled: Bool = true,
            isWorking: Bool = false,
            errorMessage: String? = nil,
            cancelTitle: String? = L10n.Common.cancel,
            secondaryTitle: String? = nil,
            onSecondary: @escaping () -> Void = {},
            destructiveTitle: String? = nil,
            onDestructive: @escaping () -> Void = {},
            width: CGFloat = MacFormSheetMetrics.width,
            layout: MacFormSheetLayout = .columns,
            isSuccess: Bool = false,
            onCancel: @escaping () -> Void,
            onConfirm: @escaping () -> Void,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.init(
                title: title,
                message: message,
                confirmTitle: confirmTitle,
                isConfirmEnabled: isConfirmEnabled,
                isWorking: isWorking,
                errorMessage: errorMessage,
                cancelTitle: cancelTitle,
                secondaryTitle: secondaryTitle,
                onSecondary: onSecondary,
                destructiveTitle: destructiveTitle,
                onDestructive: onDestructive,
                width: width,
                layout: layout,
                isSuccess: isSuccess,
                onCancel: onCancel,
                onConfirm: onConfirm,
                content: content,
                below: { EmptyView() }
            )
        }
    }

    /// A field with its error underneath, for the rows of a `MacFormSheet`.
    public struct MacFieldError: View {
        let message: String?
        var textType = Typography.TextType.body3(.regular)

        public init(message: String?) {
            self.message = message
        }

        init(message: String?, textType: Typography.TextType) {
            self.message = message
            self.textType = textType
        }

        public var body: some View {
            if let message {
                Text(message)
                    .type(textType, style: .error)
                    .contentTransition(.opacity)
                    .animation(DSMotion.stateFade, value: message)
                    .macDialogReveal()
            }
        }
    }

    public extension View {
        func macDialogReveal() -> some View {
            transition(.opacity.animation(DSMotion.stateFade))
        }

        func macDialogPop() -> some View {
            modifier(MacDialogPop())
        }
    }

    private struct MacDialogPop: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content.transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
    }

    /// The trailing buttons of a Mac dialog: an optional spinner and extra button, Cancel (Esc)
    /// and the confirm button (Return), with any leading content such as a size estimate.
    public struct MacDialogButtons<Leading: View>: View {
        /// `nil` hides the confirm button, for a state with nothing left to confirm.
        let confirmTitle: String?
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
            confirmTitle: String?,
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
                        .macDialogPop()
                }
                if let secondaryTitle {
                    Button(secondaryTitle, action: onSecondary)
                        .buttonStyle(.macDS(.secondary))
                }
                if let cancelTitle {
                    Button(cancelTitle, action: onCancel)
                        .buttonStyle(.macDS(.secondary))
                        .keyboardShortcut(.cancelAction)
                }
                if let confirmTitle {
                    Button(confirmTitle, action: onConfirm)
                        .buttonStyle(.macDS(.primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isConfirmEnabled || isWorking)
                }
            }
            .animation(DSMotion.quickFade, value: isWorking)
        }
    }

    public extension MacDialogButtons where Leading == EmptyView {
        init(
            confirmTitle: String?,
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

    #Preview("Heading") {
        VStack(alignment: .leading, spacing: .space16) {
            MacDialogHeading(title: "Two factor authentication", message: "Scan the code with your authenticator app.")
            MacDialogHeading(title: "Rename", message: nil)
        }
        .padding(.space24)
        .frame(width: MacFormSheetMetrics.width)
    }
#endif
