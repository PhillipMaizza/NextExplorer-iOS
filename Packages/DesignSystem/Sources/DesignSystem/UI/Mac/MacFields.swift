#if os(macOS)
    import AppKit
    import Localization
    import SwiftUI

    public struct MacSecureField: View {
        private let title: String
        @Binding private var text: String
        private let prompt: Text?
        private let isInvalid: Bool
        @State private var isRevealed = false
        @FocusState private var isFocused: Bool

        public init(_ title: String, text: Binding<String>, prompt: Text? = nil, isInvalid: Bool = false) {
            self.title = title
            _text = text
            self.prompt = prompt
            self.isInvalid = isInvalid
        }

        public var body: some View {
            HStack(spacing: .space8) {
                Group {
                    if isRevealed {
                        TextField(title, text: $text, prompt: prompt)
                    } else {
                        SecureField(title, text: $text, prompt: prompt)
                    }
                }
                .textFieldStyle(.plain)
                .labelsHidden()
                .type(.body2(.regular))
                .focused($isFocused)
                Button {
                    isRevealed.toggle()
                    isFocused = true
                } label: {
                    (isRevealed ? IconKit.macEyeSlash : IconKit.macEye)
                        .foregroundStyle(Color.macChromeSecondary)
                        .macSquare(.iconSmall)
                }
                .buttonStyle(.borderless)
                .help(revealLabel)
                .accessibilityLabel(revealLabel)
            }
            .padding(.leading, .space12)
            .padding(.trailing, .space8)
            .macFieldChrome(isFocused: isFocused, isInvalid: isInvalid)
            .macAccentCaret(isFocused: isFocused, isRevealed: isRevealed)
        }

        private var revealLabel: String {
            isRevealed ? L10n.Login.hidePassword : L10n.Login.showPassword
        }
    }

    private struct MacAccentCaret: NSViewRepresentable {
        let isFocused: Bool
        let isRevealed: Bool

        func makeNSView(context _: Context) -> NSView {
            NSView()
        }

        func updateNSView(_ view: NSView, context _: Context) {
            guard isFocused else { return }
            Task { @MainActor in
                (view.window?.firstResponder as? NSTextView)?.insertionPointColor = NSColor(Color.accent)
            }
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

    private enum LargeFieldConstants {
        static let shape = RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
        static let haloOpacity: Double = 0.3
        static let haloWidth: CGFloat = .size6
    }

    public extension View {
        func macAccentCaret(isFocused: Bool, isRevealed: Bool) -> some View {
            background(MacAccentCaret(isFocused: isFocused, isRevealed: isRevealed))
        }

        func macLargeField(isFocused: Bool, isInvalid: Bool = false) -> some View {
            textFieldStyle(.plain)
                .type(.body1(.regular))
                .padding(.horizontal, .space16)
                .macMinHeight(.xxLarge)
                .background(LargeFieldConstants.shape.fill(Color.macField))
                .background(
                    LargeFieldConstants.shape
                        .stroke(
                            Color.accent.opacity(LargeFieldConstants.haloOpacity),
                            lineWidth: LargeFieldConstants.haloWidth
                        )
                        .opacity(isFocused ? 1 : 0)
                )
                .overlay(
                    LargeFieldConstants.shape.strokeBorder(
                        macLargeFieldBorder(isFocused: isFocused, isInvalid: isInvalid),
                        lineWidth: isFocused ? .borderWidthFocused : .borderWidthHairline
                    )
                )
                .focusEffectDisabled()
                .animation(DSMotion.quickFade, value: isFocused)
                .animation(DSMotion.stateFade, value: isInvalid)
        }
    }

    private func macLargeFieldBorder(isFocused: Bool, isInvalid: Bool) -> Color {
        if isInvalid {
            return .negative
        }
        return isFocused ? .accentText : .macLine
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

    #Preview("Large field") {
        VStack(spacing: .space12) {
            TextField("", text: .constant(""), prompt: Text(L10n.Login.identifierField)).macLargeField(isFocused: false)
            TextField("", text: .constant("phillip")).macLargeField(isFocused: true)
            TextField("", text: .constant("phillip")).macLargeField(isFocused: false, isInvalid: true)
        }
        .padding(.space24)
        .frame(width: MacFormSheetMetrics.width)
        .macCard()
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
