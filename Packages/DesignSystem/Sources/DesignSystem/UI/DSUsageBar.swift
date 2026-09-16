import SwiftUI

private enum Constants {
    static let height: CGFloat = 6
    /// Fill switches colour as it crosses these (fraction *used*).
    static let cautionThreshold: Double = 0.7
    static let criticalThreshold: Double = 0.9
    static let fillAnimationDuration: Double = 0.35
    static let trackOpacity: Double = 0.35
}

/// A slim capsule meter for "X of Y used" figures (server disk usage). `fraction` is clamped
/// to `0...1`; the fill runs green → amber → red as the space fills up.
public struct DSUsageBar: View {
    private let fraction: Double

    public init(fraction: Double) {
        self.fraction = min(1, max(0, fraction))
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
                    .frame(width: max(Constants.height, proxy.size.width * fraction))
                    .animation(.easeOut(duration: Constants.fillAnimationDuration), value: fraction)
            }
        }
        .frame(height: Constants.height)
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
