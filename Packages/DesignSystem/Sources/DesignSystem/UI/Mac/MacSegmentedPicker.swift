#if os(macOS)
    import SwiftUI

    private enum Constants {
        static let height: CGFloat = .size32
        static let inset: CGFloat = 3
        static let gap: CGFloat = .space2
    }

    public struct MacSegmentedPicker<Value: Hashable>: View {
        private let title: String
        private let options: [Value]
        private let label: (Value) -> String
        @Binding private var selection: Value
        @Environment(\.isEnabled) private var isEnabled

        public init(
            _ title: String,
            options: [Value],
            selection: Binding<Value>,
            label: @escaping (Value) -> String
        ) {
            self.title = title
            self.options = options
            _selection = selection
            self.label = label
        }

        public var body: some View {
            HStack(spacing: Constants.gap) {
                ForEach(options, id: \.self) { option in
                    segment(option)
                }
            }
            .padding(Constants.inset)
            .background(Capsule().fill(Color.macSegment))
            .fixedSize()
            .opacity(isEnabled ? 1 : MacOpacity.disabled)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }

        private func segment(_ option: Value) -> some View {
            let isSelected = option == selection
            return Button {
                selection = option
            } label: {
                Text(label(option))
                    .type(.label4)
                    .foregroundStyle(isSelected ? Color.onAccent : Color.macChromeText)
                    .padding(.horizontal, .space12)
                    .frame(height: Constants.height)
                    .background(Capsule().fill(isSelected ? Color.accent : .clear))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .animation(DSMotion.quickFade, value: isSelected)
        }
    }

    #Preview("Segmented picker") {
        @Previewable @State var selection = 0
        VStack(spacing: .space16) {
            MacSegmentedPicker("Access", options: [0, 1], selection: $selection) { $0 == 0
                ? "Read only"
                : "Read and write"
            }
            MacSegmentedPicker("Access", options: [0, 1], selection: $selection) { $0 == 0
                ? "Read only"
                : "Read and write"
            }
            .disabled(true)
        }
        .padding(.space24)
        .background(Color.macCard)
    }
#endif
