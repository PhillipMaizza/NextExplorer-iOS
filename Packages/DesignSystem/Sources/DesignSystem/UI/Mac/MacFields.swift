#if os(macOS)
    import Localization
    import SwiftUI

    public struct MacSecureField: View {
        private let title: String
        @Binding private var text: String
        private let prompt: Text?
        @State private var isRevealed = false
        @FocusState private var isFocused: Bool

        public init(_ title: String, text: Binding<String>, prompt: Text? = nil) {
            self.title = title
            _text = text
            self.prompt = prompt
        }

        public var body: some View {
            HStack(spacing: .space4) {
                Group {
                    if isRevealed {
                        TextField(title, text: $text, prompt: prompt)
                    } else {
                        SecureField(title, text: $text, prompt: prompt)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .type(.body2(.regular))
                .focused($isFocused)
                Button {
                    isRevealed.toggle()
                    isFocused = true
                } label: {
                    (isRevealed ? IconKit.eyeSlash : IconKit.eye)
                        .foregroundStyle(Color.macChromeSecondary)
                        .frame(width: .iconSmall, height: .iconSmall)
                }
                .buttonStyle(.borderless)
                .help(revealLabel)
                .accessibilityLabel(revealLabel)
            }
        }

        private var revealLabel: String {
            isRevealed ? L10n.Login.hidePassword : L10n.Login.showPassword
        }
    }

    public struct MacPathField: View {
        private let path: String?
        private let placeholder: String
        private let onChoose: () -> Void

        public init(path: String?, placeholder: String, onChoose: @escaping () -> Void) {
            self.path = path
            self.placeholder = placeholder
            self.onChoose = onChoose
        }

        public var body: some View {
            HStack(spacing: .space8) {
                Text(path ?? placeholder)
                    .type(.body2(.regular), style: path == nil ? .secondary : .primaryOnSurface)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: .space8)
                Button(L10n.MacSettings.choose, action: onChoose)
                    .buttonStyle(.macDS(.secondary, size: .small))
            }
        }
    }

    #Preview("Secure field") {
        struct Demo: View {
            @State private var empty = ""
            @State private var filled = "hunter2"

            var body: some View {
                Form {
                    LabeledContent(L10n.Common.password) {
                        MacSecureField(L10n.Common.password, text: $empty)
                    }
                    LabeledContent(L10n.Common.password) {
                        MacSecureField(L10n.Common.password, text: $filled)
                    }
                    LabeledContent(L10n.Common.password) {
                        MacSecureField(L10n.Common.password, text: $filled).disabled(true)
                    }
                }
                .formStyle(.columns)
                .padding(.space24)
                .frame(width: MacFormSheetMetrics.width)
            }
        }
        return Demo()
    }

    #Preview("Path field") {
        Form {
            LabeledContent(L10n.Uploads.reviewSectionPath) {
                MacPathField(path: nil, placeholder: L10n.Uploads.reviewChooseFolder) {}
            }
            LabeledContent(L10n.Uploads.reviewSectionPath) {
                MacPathField(path: "/Documents/Invoices/2026", placeholder: L10n.Uploads.reviewChooseFolder) {}
            }
        }
        .formStyle(.columns)
        .padding(.space24)
        .frame(width: MacFormSheetMetrics.width)
    }
#endif
