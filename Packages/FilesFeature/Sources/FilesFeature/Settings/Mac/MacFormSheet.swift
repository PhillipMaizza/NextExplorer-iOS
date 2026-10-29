#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 480
        static let padding: CGFloat = .space24
        static let spacing: CGFloat = .space16
    }

    /// A native Mac sheet around a form: its title, the labeled fields, any error, then Cancel
    /// (Esc) and the confirm button (Return) at the trailing edge.
    struct MacFormSheet<Content: View>: View {
        let title: String
        let confirmTitle: String
        var isConfirmEnabled = true
        var isWorking = false
        var errorMessage: String?
        var cancelTitle = L10n.Common.cancel
        var width: CGFloat = Metrics.width
        let onCancel: () -> Void
        let onConfirm: () -> Void
        @ViewBuilder let content: () -> Content

        var body: some View {
            VStack(alignment: .leading, spacing: Metrics.spacing) {
                Text(title).font(.headline)
                Form {
                    content()
                }
                .formStyle(.columns)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color.negativeText)
                }
                HStack(spacing: .space8) {
                    Spacer()
                    if isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Button(cancelTitle, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button(confirmTitle, action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isConfirmEnabled || isWorking)
                }
            }
            .padding(Metrics.padding)
            .frame(width: width)
        }
    }

    /// A field with its error underneath, for the rows of a `MacFormSheet`.
    struct MacFieldError: View {
        let message: String?

        var body: some View {
            if let message {
                Text(message).font(.callout).foregroundStyle(Color.negativeText)
            }
        }
    }

    #Preview("Form sheet") {
        MacFormSheet(title: "Create User", confirmTitle: "Create User", onCancel: {}, onConfirm: {}) {
            TextField("Email:", text: .constant(""))
            SecureField("Password:", text: .constant(""))
        }
    }
#endif
