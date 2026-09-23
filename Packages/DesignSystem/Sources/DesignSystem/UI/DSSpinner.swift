import SwiftUI

private enum Constants {
    static let trimEnd: CGFloat = 0.75
    static let trackOpacity: Double = 0.2
    static let rotationDuration: Double = 0.85
    static let fullRotation: Double = 360

    static let smallDiameter: CGFloat = .iconSmall
    static let regularDiameter: CGFloat = .size20
    static let largeDiameter: CGFloat = .iconLarge

    static let smallLineWidth: CGFloat = 2
    static let regularLineWidth: CGFloat = 2.5
    static let largeLineWidth: CGFloat = 3.5
}

/// The app's indeterminate activity indicator: a three quarter (270°) circular arc with rounded
/// caps that spins continuously. Replaces the default `ProgressView()` everywhere an indeterminate
/// spinner is shown. Determinate progress (`ProgressView(value:)`) keeps its own bar.
///
/// `color` defaults to `accent`; pass a contrasting color inside filled buttons (white on the
/// primary accent fill, black on inverted). Sizes map to the three `controlSize` footprints used
/// across the app.
public struct DSSpinner: View {
    public enum Size {
        case small
        case regular
        case large
    }

    private let size: Size
    private let color: Color
    private let accessibilityLabel: String

    /// `accessibilityLabel` defaults to the English "Loading"; localized call sites pass their own
    /// `L10n` string so this component stays free of an app copy dependency.
    public init(size: Size = .regular, color: Color = .accent, accessibilityLabel: String = "Loading") {
        self.size = size
        self.color = color
        self.accessibilityLabel = accessibilityLabel
    }

    @State private var isAnimating = false

    private var diameter: CGFloat {
        switch size {
        case .small: Constants.smallDiameter
        case .regular: Constants.regularDiameter
        case .large: Constants.largeDiameter
        }
    }

    private var lineWidth: CGFloat {
        switch size {
        case .small: Constants.smallLineWidth
        case .regular: Constants.regularLineWidth
        case .large: Constants.largeLineWidth
        }
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(Constants.trackOpacity), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: Constants.trimEnd)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                // Scoped to the rotation alone: a value based animation also caught the spinner's
                // first placement in a still sizing window, sliding it in from the top left.
                .animation(.linear(duration: Constants.rotationDuration).repeatForever(autoreverses: false)) {
                    $0.rotationEffect(.degrees(isAnimating ? Constants.fullRotation : 0))
                }
        }
        .frame(width: diameter, height: diameter)
        .onAppear { isAnimating = true }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("Sizes") {
    HStack(spacing: .space24) {
        DSSpinner(size: .small)
        DSSpinner(size: .regular)
        DSSpinner(size: .large)
    }
    .padding()
}

#Preview("On accent") {
    ZStack {
        Color.accent
        DSSpinner(color: .white)
    }
    .frame(width: 120, height: 120)
}
