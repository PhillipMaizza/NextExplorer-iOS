import SwiftUI

private enum SegmentedControlConstants {
    static let height: CGFloat = .size40
    static let fadeDuration: Double = 0.2
}

/// A pill-shaped segmented control — accent-filled selected segment on a `backgroundSecondary`
/// track. Generic over any `Hashable` option set (e.g. an enum of modes).
public struct DSSegmentedControl<Option: Hashable>: View {
    private let options: [Option]
    private let label: (Option) -> String
    @Binding private var selection: Option

    public init(options: [Option], selection: Binding<Option>, label: @escaping (Option) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    public var body: some View {
        HStack(spacing: .space4) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .type(.body2)
                        .foregroundStyle(isSelected ? .white : Color.primaryDS)
                        .frame(maxWidth: .infinity)
                        .frame(height: SegmentedControlConstants.height)
                        .background(
                            RoundedRectangle(cornerRadius: .radiusFull)
                                .fill(isSelected ? Color.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.space4)
        .background(RoundedRectangle(cornerRadius: .radiusFull).fill(Color.backgroundSecondary))
        .animation(.easeInOut(duration: SegmentedControlConstants.fadeDuration), value: selection)
    }
}
