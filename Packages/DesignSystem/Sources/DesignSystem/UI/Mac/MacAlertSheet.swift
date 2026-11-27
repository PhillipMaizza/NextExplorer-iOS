#if os(macOS)
    import CoreModels
    import Localization
    import SwiftUI

    private enum Constants {
        static let width: CGFloat = 280
        static let logoSize: CGFloat = .size56
        static let logoRadius: CGFloat = .radiusMedium
        static let glyphSize: CGFloat = .size24
        static let topPadding: CGFloat = .space24
        static let sidePadding: CGFloat = .space16
        static let bottomPadding: CGFloat = .space16
        static let buttonHeight: CGFloat = .size32
    }

    public struct MacAlertSheet<Accessory: View>: View {
        let glyph: Image?
        let title: String
        let message: String?
        let confirmTitle: String
        let cancelTitle: String
        let neutralTitle: String?
        let isDestructive: Bool
        let isConfirmLoading: Bool
        let isConfirmDisabled: Bool
        let accessory: Accessory
        let onConfirm: () -> Void
        let onNeutral: (() -> Void)?
        let onCancel: () -> Void

        public init(
            glyph: Image? = nil,
            title: String,
            message: String?,
            confirmTitle: String,
            cancelTitle: String = L10n.Common.cancel,
            neutralTitle: String? = nil,
            isDestructive: Bool = true,
            isConfirmLoading: Bool = false,
            isConfirmDisabled: Bool = false,
            onConfirm: @escaping () -> Void,
            onNeutral: (() -> Void)? = nil,
            onCancel: @escaping () -> Void,
            @ViewBuilder accessory: () -> Accessory
        ) {
            self.glyph = glyph
            self.title = title
            self.message = message
            self.confirmTitle = confirmTitle
            self.cancelTitle = cancelTitle
            self.neutralTitle = neutralTitle
            self.isDestructive = isDestructive
            self.isConfirmLoading = isConfirmLoading
            self.isConfirmDisabled = isConfirmDisabled
            self.accessory = accessory()
            self.onConfirm = onConfirm
            self.onNeutral = onNeutral
            self.onCancel = onCancel
        }

        public var body: some View {
            VStack(spacing: .space8) {
                icon
                    .frame(width: Constants.logoSize, height: Constants.logoSize)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.logoRadius, style: .continuous))
                    .padding(.bottom, .space4)
                    .accessibilityHidden(true)
                Text(title)
                    .type(.body2(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .type(.body3(.regular), style: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                accessory
                    .multilineTextAlignment(.leading)
                    .padding(.top, .space4)
                VStack(spacing: .space8) {
                    Button(action: onConfirm) {
                        ZStack {
                            Text(confirmTitle).opacity(isConfirmLoading ? 0 : 1)
                            if isConfirmLoading {
                                MacSpinner()
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: Constants.buttonHeight)
                    }
                    .buttonStyle(.macDS(isDestructive ? .failure : .primary, size: .small))
                    .disabled(isConfirmDisabled)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Alert.confirm)
                    if let neutralTitle, let onNeutral {
                        button(neutralTitle, style: .secondary, action: onNeutral)
                    }
                    button(cancelTitle, style: .secondary, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                .disabled(isConfirmLoading)
                .padding(.top, .space8)
            }
            .multilineTextAlignment(.center)
            .padding(.top, Constants.topPadding)
            .padding(.horizontal, Constants.sidePadding)
            .padding(.bottom, Constants.bottomPadding)
            .frame(width: Constants.width)
            .interactiveDismissDisabled()
        }

        @ViewBuilder private var icon: some View {
            if let glyph {
                glyph
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.glyphSize, height: Constants.glyphSize)
                    .foregroundStyle(Color.macTagBlue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.macTagBlueFill)
            } else {
                IconKit.logo.resizable()
            }
        }

        private func button(_ title: String, style: DSButtonStyle, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(title).frame(maxWidth: .infinity, minHeight: Constants.buttonHeight)
            }
            .buttonStyle(.macDS(style, size: .small))
        }
    }

    public extension MacAlertSheet where Accessory == EmptyView {
        init(
            title: String,
            message: String?,
            confirmTitle: String,
            cancelTitle: String = L10n.Common.cancel,
            neutralTitle: String? = nil,
            isDestructive: Bool = true,
            isConfirmLoading: Bool = false,
            onConfirm: @escaping () -> Void,
            onNeutral: (() -> Void)? = nil,
            onCancel: @escaping () -> Void
        ) {
            self.init(
                title: title,
                message: message,
                confirmTitle: confirmTitle,
                cancelTitle: cancelTitle,
                neutralTitle: neutralTitle,
                isDestructive: isDestructive,
                isConfirmLoading: isConfirmLoading,
                onConfirm: onConfirm,
                onNeutral: onNeutral,
                onCancel: onCancel,
                accessory: { EmptyView() }
            )
        }
    }

    #Preview("Alert") {
        MacAlertSheet(
            title: "Revoke Token?",
            message: "Anything using \"home automation\" will stop working right away. This can't be undone.",
            confirmTitle: "Revoke",
            onConfirm: {},
            onCancel: {}
        )
        .background(Color.macCard)
    }

    #Preview("Alert with a third choice") {
        MacAlertSheet(
            title: "Sign Out?",
            message: nil,
            confirmTitle: "Sign Out",
            neutralTitle: "Sign Out and Keep Offline Files",
            onConfirm: {},
            onNeutral: {},
            onCancel: {}
        )
        .background(Color.macCard)
    }

    #Preview("Alert working") {
        MacAlertSheet(
            title: "Empty the Trash?",
            message: "Everything in the trash is deleted for good.",
            confirmTitle: "Empty Trash",
            isConfirmLoading: true,
            onConfirm: {},
            onCancel: {}
        )
        .background(Color.macCard)
    }

    #Preview("Alert with a field") {
        MacAlertSheet(
            glyph: IconKit.lock,
            title: "Password required",
            message: "This archive is protected. Enter its password to extract it.",
            confirmTitle: "Extract",
            isDestructive: false,
            onConfirm: {},
            onCancel: {},
            accessory: {
                VStack(alignment: .leading, spacing: .space4) {
                    MacSecureField("Archive password", text: .constant("secret"), isInvalid: true)
                    Text("Incorrect password, or the archive is damaged.")
                        .type(.caption(.regular), style: .error)
                }
            }
        )
        .background(Color.macCard)
    }
#endif
