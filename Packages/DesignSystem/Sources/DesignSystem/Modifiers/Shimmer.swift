import SwiftUI

private enum Constants {
    static let sweepDuration: Double = 1.5
    static let bandWidthFraction: CGFloat = 0.7
    static let ghostOpacity: Double = 0.35
    static let shineOpacity: Double = 0.75
}

public extension View {
    /// Holds the view at a low resting opacity and sweeps a soft highlight band across it,
    /// left to right, forever — a loading skeleton. Pair with `.redacted(reason: .placeholder)`
    /// so real content collapses to plain bars first. Under Reduce Motion the sweep is dropped
    /// and only the resting ghost remains.
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .opacity(Constants.ghostOpacity)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let bandWidth = proxy.size.width * Constants.bandWidthFraction
                        LinearGradient(
                            colors: [.clear, .white.opacity(Constants.shineOpacity), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: bandWidth)
                        .offset(x: phase * (proxy.size.width + bandWidth))
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                    }
                    .mask(content)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: Constants.sweepDuration).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: .space16) {
        ForEach(0..<5, id: \.self) { _ in
            HStack(spacing: .space12) {
                RoundedRectangle(cornerRadius: .radiusSmall)
                    .frame(width: .iconMedium, height: .iconMedium)
                VStack(alignment: .leading, spacing: .space8) {
                    RoundedRectangle(cornerRadius: .radiusXSmall).frame(width: .size96, height: .size12)
                    RoundedRectangle(cornerRadius: .radiusXSmall).frame(width: .size64, height: .size12)
                }
            }
            .foregroundStyle(Color.secondaryDS)
        }
    }
    .shimmering()
    .padding(.space16)
}
