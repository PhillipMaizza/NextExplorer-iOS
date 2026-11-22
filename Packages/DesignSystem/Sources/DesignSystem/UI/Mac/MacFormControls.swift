#if os(macOS)
    import Localization
    import SwiftUI

    private enum Constants {
        static let fieldHeight: CGFloat = 34
        static let popupHeight: CGFloat = .size32
        static let focusHaloWidth: CGFloat = 3
        static let focusHaloOpacity: Double = 0.32
        static let shape = RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
    }

    public struct MacTextField: View {
        private let title: String
        @Binding private var text: String
        private let prompt: String?
        @FocusState private var isFocused: Bool
        @Environment(\.isEnabled) private var isEnabled

        public init(_ title: String, text: Binding<String>, prompt: String? = nil) {
            self.title = title
            _text = text
            self.prompt = prompt
        }

        public var body: some View {
            TextField(title, text: $text, prompt: prompt.map { Text($0).foregroundStyle(Color.macChromeSecondary) })
                .textFieldStyle(.plain)
                .labelsHidden()
                .type(.body2(.regular))
                .focused($isFocused)
                .tint(Color.accent)
                .padding(.horizontal, .space12)
                .frame(height: Constants.fieldHeight)
                .background(Constants.shape.fill(Color.macField))
                .background(
                    Constants.shape
                        .stroke(
                            Color.accent.opacity(Constants.focusHaloOpacity),
                            lineWidth: Constants.focusHaloWidth
                        )
                        .opacity(isFocused ? 1 : 0)
                )
                .overlay(
                    Constants.shape.strokeBorder(
                        isFocused ? Color.accent : .macLine,
                        lineWidth: .borderWidthHairline
                    )
                )
                .focusEffectDisabled()
                .opacity(isEnabled ? 1 : MacOpacity.disabled)
        }
    }

    public struct MacPopup<Value: Hashable, Options: View>: View {
        private let title: String
        private let valueLabel: String
        @Binding private var selection: Value
        private let options: () -> Options
        @Environment(\.isEnabled) private var isEnabled

        public init(
            _ title: String,
            valueLabel: String,
            selection: Binding<Value>,
            @ViewBuilder options: @escaping () -> Options
        ) {
            self.title = title
            self.valueLabel = valueLabel
            _selection = selection
            self.options = options
        }

        public var body: some View {
            Menu {
                Picker(title, selection: $selection) { options() }
                    .pickerStyle(.inline)
                    .labelsHidden()
            } label: {
                HStack(spacing: .space8) {
                    Text(valueLabel)
                        .type(.body2(.regular))
                    IconKit.chevronUpDown
                        .imageScale(.small)
                        .foregroundStyle(Color.macChromeSecondary)
                }
                .padding(.leading, .space12)
                .padding(.trailing, .space8)
                .frame(height: Constants.popupHeight)
                .background(Constants.shape.fill(Color.macField))
                .overlay(Constants.shape.strokeBorder(Color.macLine, lineWidth: .borderWidthHairline))
                .contentShape(Constants.shape)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(isEnabled ? 1 : MacOpacity.disabled)
            .accessibilityLabel(title)
            .accessibilityValue(valueLabel)
        }
    }

    #Preview("Field and popup") {
        HStack(spacing: .space8) {
            MacTextField("Search", text: .constant(""), prompt: "A name or a path")
                .frame(width: 240)
            MacPopup("Kind", valueLabel: "Any kind", selection: .constant(0)) {
                Text(verbatim: "Any kind").tag(0)
                Text(verbatim: "Uploaded").tag(1)
            }
            MacPopup("Outcome", valueLabel: "Any outcome", selection: .constant(0)) {
                Text(verbatim: "Any outcome").tag(0)
            }
            .disabled(true)
        }
        .padding()
        .background(Color.macCard)
    }
#endif
