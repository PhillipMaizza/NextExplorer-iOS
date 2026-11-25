import SwiftUI

private enum Constants {
    /// Fill switches colour as it crosses these (fraction *used*).
    static let cautionThreshold: Double = 0.7
    static let criticalThreshold: Double = 0.9
    static let trackOpacity: Double = .opacityDim
}

/// A slim capsule meter for "X of Y used" figures (server disk usage). `fraction` is clamped
/// to `0...1`; the fill runs green → amber → red as the space fills up.
public struct DSUsageBar: View {
    private let fraction: Double
    private let height: CGFloat

    /// Drives the fill so it grows in from empty on first appear, and eases to a new value on change.
    @State private var displayFraction: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(fraction: Double, height: CGFloat = .size6) {
        self.fraction = min(1, max(0, fraction))
        self.height = height
    }

    private var fillColor: Color {
        switch fraction {
        case ..<Constants.cautionThreshold: .positive
        case ..<Constants.criticalThreshold: .attention
        default: .negative
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.borderPrimary.opacity(Constants.trackOpacity))
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(height, proxy.size.width * displayFraction))
                    .animation(
                        reduceMotion ? nil : DSMotion.appear,
                        value: displayFraction
                    )
                    .animation(
                        reduceMotion ? nil : DSMotion.appear,
                        value: fillColor
                    )
            }
        }
        .frame(height: height)
        // Starts at 0 (see `displayFraction`), so this first assignment grows the fill in from empty.
        .onAppear { displayFraction = fraction }
        .onChange(of: fraction) { _, new in displayFraction = new }
        .accessibilityElement()
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ForEach([0.08, 0.45, 0.7, 0.82, 0.9, 0.97], id: \.self) { value in
            VStack(alignment: .leading, spacing: 4) {
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .type(.caption(.regular), style: .secondary)
                DSUsageBar(fraction: value)
            }
        }
    }
    .padding()
}
