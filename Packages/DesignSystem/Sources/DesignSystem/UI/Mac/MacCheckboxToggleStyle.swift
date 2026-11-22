#if os(macOS)
    import SwiftUI

    private enum Constants {
        static let boxSize: CGFloat = .size16
        static let glyphSize: CGFloat = 9
        static let shape = RoundedRectangle(cornerRadius: .radiusXSmall, style: .continuous)
    }

    public struct MacCheckboxToggleStyle: ToggleStyle {
        public init() {}

        public func makeBody(configuration: Configuration) -> some View {
            MacCheckbox(configuration: configuration)
        }
    }

    private struct MacCheckbox: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Button {
                configuration.isOn.toggle()
            } label: {
                HStack(spacing: .space8) {
                    Constants.shape
                        .fill(configuration.isOn ? Color.accent : Color.macField)
                        .overlay(Constants.shape.strokeBorder(
                            configuration.isOn ? Color.clear : Color.macLine,
                            lineWidth: .borderWidthHairline
                        ))
                        .overlay {
                            if configuration.isOn {
                                IconKit.checkmark
                                    .resizable()
                                    .scaledToFit()
                                    .fontWeight(.bold)
                                    .frame(width: Constants.glyphSize, height: Constants.glyphSize)
                                    .foregroundStyle(Color.onAccent)
                            }
                        }
                        .frame(width: Constants.boxSize, height: Constants.boxSize)
                    configuration.label
                        .type(.body2(.regular))
                        .foregroundStyle(Color.macChromeText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : MacOpacity.disabled)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
        }
    }

    public extension ToggleStyle where Self == MacCheckboxToggleStyle {
        static var macCheckbox: Self {
            MacCheckboxToggleStyle()
        }
    }

    #Preview("Checkboxes") {
        @Previewable @State var isOn = true
        VStack(alignment: .leading, spacing: .space12) {
            Toggle("Apply to Subfolders", isOn: $isOn)
            Toggle("Apply to Subfolders", isOn: .constant(false))
            Toggle("Apply to Subfolders", isOn: .constant(true)).disabled(true)
        }
        .toggleStyle(.macCheckbox)
        .padding(.space24)
        .background(Color.macCard)
    }
#endif
