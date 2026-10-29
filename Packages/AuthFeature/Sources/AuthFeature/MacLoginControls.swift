#if os(macOS)
    import DesignSystem
    import SwiftUI

    /// A full width native push button for the login card, with a spinner beside the title
    /// while its step runs. Return triggers the prominent one.
    struct MacLoginButton: View {
        let title: String
        var systemImage: String?
        let isWorking: Bool
        let isProminent: Bool
        let action: () -> Void

        var body: some View {
            if isProminent {
                button
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                button.buttonStyle(.bordered)
            }
        }

        private var button: some View {
            Button(action: action) {
                HStack(spacing: .space8) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else if let systemImage {
                        Image(systemName: systemImage)
                    }
                    Text(title)
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
    }

    /// A native rounded text field with its label above, shaking and outlined in red when
    /// the server rejected what it holds.
    struct MacLoginField<Field: View>: View {
        let label: String
        let shakeTrigger: CGFloat
        let isInvalid: Bool
        @ViewBuilder let field: () -> Field

        var body: some View {
            VStack(alignment: .leading, spacing: .space4) {
                Text(label).font(.callout).foregroundStyle(.secondary)
                field()
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .overlay {
                        if isInvalid {
                            RoundedRectangle(cornerRadius: .radiusSmall)
                                .strokeBorder(Color.negative, lineWidth: 1)
                        }
                    }
                    .shake(trigger: shakeTrigger)
            }
        }
    }
#endif
