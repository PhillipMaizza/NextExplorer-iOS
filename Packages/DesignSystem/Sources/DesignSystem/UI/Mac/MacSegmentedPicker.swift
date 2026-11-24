#if os(macOS)
    import SwiftUI

    private enum Constants {
        static let height: CGFloat = .size32
        static let inset: CGFloat = 3
        static let gap: CGFloat = .space2
        static let pillID = "pill"
    }

    public struct MacSegmentedPicker<Value: Hashable>: View {
        private let title: String
        private let options: [Value]
        private let label: (Value) -> String
        private let isFullWidth: Bool
        @Binding private var selection: Value
        @Namespace private var pill

        public init(
            _ title: String,
            options: [Value],
            selection: Binding<Value>,
            isFullWidth: Bool = false,
            label: @escaping (Value) -> String
        ) {
            self.title = title
            self.options = options
            _selection = selection
            self.isFullWidth = isFullWidth
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
            .fixedSize(horizontal: !isFullWidth, vertical: true)
            .macDisabledDim()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }

        private func segment(_ option: Value) -> some View {
            let isSelected = option == selection
            return Button {
                withAnimation(DSMotion.controlMorph) { selection = option }
            } label: {
                Text(label(option))
                    .type(.label4)
                    .foregroundStyle(isSelected ? Color.onAccent : Color.macChromeText)
                    .padding(.horizontal, .space12)
                    .frame(maxWidth: isFullWidth ? .infinity : nil)
                    .frame(height: Constants.height)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.accent)
                                .matchedGeometryEffect(id: Constants.pillID, in: pill)
                        }
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            MacSegmentedPicker("Mode", options: [0, 1, 2], selection: $selection, isFullWidth: true) {
                "Option \($0 + 1)"
            }
        }
        .padding(.space24)
        .background(Color.macCard)
    }
#endif
