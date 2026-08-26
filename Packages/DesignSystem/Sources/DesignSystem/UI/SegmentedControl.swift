import SwiftUI

private enum SegmentedControlConstants {
    static let height: CGFloat = .size40
    /// Matches `DSAnimatedButton`'s morph spring (`Buttons.swift`) so every "shape slides
    /// into place" moment in the app shares the same feel.
    static let pillSpringResponse: Double = 0.35
    static let pillSpringDamping: Double = 0.8
}

/// A pill-shaped segmented control: accent-filled selected segment on a `backgroundSecondary`
/// track. Generic over any `Hashable` option set (e.g. an enum of modes). The accent pill is a
/// single view that slides between segments via `matchedGeometryEffect` rather than each
/// segment independently fading its own background in/out.
public struct DSSegmentedControl<Option: Hashable>: View {
    private let options: [Option]
    private let label: (Option) -> String
    @Binding private var selection: Option
    @Namespace private var pillNamespace
    private static var pillID: String { "pill" }

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
                        .type(.body2(isSelected ? .bold : .regular))
                        .foregroundStyle(Color.primaryDS)
                        .frame(maxWidth: .infinity)
                        .frame(height: SegmentedControlConstants.height)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: .radiusFull)
                                    .fill(Color.accent)
                                    .matchedGeometryEffect(id: Self.pillID, in: pillNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.space4)
        .background(RoundedRectangle(cornerRadius: .radiusFull).fill(Color.backgroundSecondary))
        .animation(
            .spring(response: SegmentedControlConstants.pillSpringResponse, dampingFraction: SegmentedControlConstants.pillSpringDamping),
            value: selection
        )
        .hapticFeedback(.selection, trigger: selection)
    }
}
