import SwiftUI

private enum Constants {
    /// Bounce playback speed on select/deselect; >1 makes the pop snappier.
    static let bounceSpeed: Double = 1.8
    /// How small a row's circle shrinks as it leaves, while its column narrows to nothing.
    static let hiddenScale: CGFloat = 0.5
}

/// The circular selection glyph shown on the leading edge of a row (or a grid cell overlay)
/// while a list is in multi select mode: a filled accent checkmark when selected, a hollow
/// secondary ring when not, with a bounce on change and a scale/opacity transition on
/// insertion. Shared by the browse, favorites and downloads lists and the share user pickers.
public struct DSSelectionIndicator: View {
    private let isSelected: Bool
    private let size: CGFloat

    public init(isSelected: Bool, size: CGFloat = .size20) {
        self.isSelected = isSelected
        self.size = size
    }

    public var body: some View {
        (isSelected ? IconKit.checkmarkCircleFill : IconKit.radioUnselected)
            .resizable()
            .scaledToFit()
            .foregroundStyle(isSelected ? Color.accentText : Color.secondaryDS)
            .frame(width: size, height: size)
            .symbolEffect(.bounce, options: .speed(Constants.bounceSpeed), value: isSelected)
            .transition(.scale.combined(with: .opacity))
    }
}

public extension View {
    /// A list row's selection circle on its leading edge. It is always part of the row, only
    /// narrowed to nothing outside select mode, so entering it slides the row over instead of
    /// rebuilding the row, which made the list flash.
    func dsListSelection(isSelecting: Bool, isSelected: Bool) -> some View {
        modifier(ListSelectionModifier(isSelecting: isSelecting, isSelected: isSelected))
    }

    /// A grid cell's selection circle while selecting: in its top leading corner, centered on the
    /// card's corner curve so the two stay concentric, as system badges do.
    func dsGridSelection(isSelecting: Bool, isSelected: Bool) -> some View {
        modifier(GridSelectionModifier(isSelecting: isSelecting, isSelected: isSelected))
    }
}

private struct ListSelectionModifier: ViewModifier {
    let isSelecting: Bool
    let isSelected: Bool
    @Environment(\.selectionIndicatorsShown) private var indicatorsShown

    /// Seeded from `isSelecting`, so a row that appears while selecting has its circle from its first
    /// frame instead of sliding it in.
    init(isSelecting: Bool, isSelected: Bool) {
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        _isShown = State(initialValue: isSelecting)
    }

    /// The row's own copy, animated from inside the cell: a List applies a row's new input as a
    /// plain cell update, so an animation that comes with the input never reaches the circle.
    @State private var isShown = false

    func body(content: Content) -> some View {
        HStack(spacing: isShown ? .space12 : 0) {
            // Shrunk and faded rather than clipped: a clip cut the select bounce square.
            DSSelectionIndicator(isSelected: isSelected)
                .scaleEffect(isShown ? 1 : Constants.hiddenScale, anchor: .leading)
                .opacity(isShown ? 1 : 0)
                .frame(width: isShown ? .size20 : 0, alignment: .leading)
                .accessibilityHidden(!isShown)
            content
        }
        .onAppear { isShown = indicatorsShown ?? isSelecting }
        .onChange(of: indicatorsShown ?? isSelecting) { _, isShown in
            withAnimation(DSMotion.selectModeStep) { self.isShown = isShown }
        }
    }
}

private struct GridSelectionModifier: ViewModifier {
    let isSelecting: Bool
    let isSelected: Bool
    @Environment(\.selectionIndicatorsShown) private var indicatorsShown

    /// Seeded from `isSelecting`, so a row that appears while selecting has its circle from its first
    /// frame instead of sliding it in.
    init(isSelecting: Bool, isSelected: Bool) {
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        _isShown = State(initialValue: isSelecting)
    }

    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if isShown {
                    DSSelectionIndicator(isSelected: isSelected)
                        .padding(max(.space4, .radiusCard - .size20 / 2))
                }
            }
            .onAppear { isShown = indicatorsShown ?? isSelecting }
            .onChange(of: indicatorsShown ?? isSelecting) { _, isShown in
                withAnimation(DSMotion.selectModeStep) { self.isShown = isShown }
            }
    }
}

#Preview {
    HStack(spacing: .space16) {
        DSSelectionIndicator(isSelected: true)
        DSSelectionIndicator(isSelected: false)
        DSSelectionIndicator(isSelected: true, size: .iconSmall)
    }
    .padding()
    .background(Color.backgroundPrimary)
}

#Preview("Grid cell") {
    Color.backgroundSecondary
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: .radiusLarge))
        .dsGridSelection(isSelecting: true, isSelected: true)
        .padding()
        .background(Color.backgroundPrimary)
}
