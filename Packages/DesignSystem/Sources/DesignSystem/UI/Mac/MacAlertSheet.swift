#if os(macOS)
    import Localization
    import SwiftUI

    private enum Constants {
        static let width: CGFloat = 280
        static let logoSize: CGFloat = .size56
        static let logoRadius: CGFloat = 14
        static let topPadding: CGFloat = 22
        static let sidePadding: CGFloat = 18
        static let bottomPadding: CGFloat = .space16
        static let buttonHeight: CGFloat = .size32
    }

    public struct MacAlertSheet: View {
        let title: String
        let message: String
        let confirmTitle: String
        let isDestructive: Bool
        let onConfirm: () -> Void
        let onCancel: () -> Void

        public init(
            title: String,
            message: String,
            confirmTitle: String,
            isDestructive: Bool = true,
            onConfirm: @escaping () -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.title = title
            self.message = message
            self.confirmTitle = confirmTitle
            self.isDestructive = isDestructive
            self.onConfirm = onConfirm
            self.onCancel = onCancel
        }

        public var body: some View {
            VStack(spacing: .space8) {
                IconKit.logo
                    .resizable()
                    .frame(width: Constants.logoSize, height: Constants.logoSize)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.logoRadius, style: .continuous))
                    .padding(.bottom, .space4)
                    .accessibilityHidden(true)
                Text(title)
                    .type(.body2(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .type(.body3(.regular), style: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: .space8) {
                    button(confirmTitle, style: isDestructive ? .failure : .primary, action: onConfirm)
                    button(L10n.Common.cancel, style: .secondary, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.top, .space8)
            }
            .multilineTextAlignment(.center)
            .padding(.top, Constants.topPadding)
            .padding(.horizontal, Constants.sidePadding)
            .padding(.bottom, Constants.bottomPadding)
            .frame(width: Constants.width)
        }

        private func button(_ title: String, style: DSButtonStyle, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(title).frame(maxWidth: .infinity, minHeight: Constants.buttonHeight)
            }
            .buttonStyle(.macDS(style, size: .small))
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
#endif
