import SwiftUI

private enum Constants {
    /// Bounce playback speed on select/deselect; >1 makes the pop snappier.
    static let bounceSpeed: Double = 1.8
}

/// The circular selection glyph shown on the leading edge of a row (or a grid cell overlay)
/// while a list is in multi select mode: a filled accent checkmark when selected, a hollow
/// secondary ring when not, with a bounce on change and a scale/opacity transition on
/// insertion. Shared by the browse, favorites and downloads lists and the share user pickers.
public struct DSSelectionIndicator: View {
    private let isSelected: Bool
    private let size: CGFloat

    public init(isSelected: Bool, size: CGFloat = .iconMedium) {
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

#Preview {
    HStack(spacing: .space16) {
        DSSelectionIndicator(isSelected: true)
        DSSelectionIndicator(isSelected: false)
        DSSelectionIndicator(isSelected: true, size: .iconSmall)
    }
    .padding()
    .background(Color.backgroundPrimary)
}
