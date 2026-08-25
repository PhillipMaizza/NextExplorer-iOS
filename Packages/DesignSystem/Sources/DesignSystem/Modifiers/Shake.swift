import SwiftUI

/// Classic SwiftUI shake: `animatableData` sweeping from one integer to the next drives a
/// damped sine wave, so incrementing a `@State` counter under `withAnimation` triggers exactly
/// one shake burst. Use via `.shake(trigger:)` below rather than the raw modifier.
public struct ShakeEffect: GeometryEffect {
    public var travelDistance: CGFloat
    public var numberOfShakes: CGFloat
    public var animatableData: CGFloat

    public init(travelDistance: CGFloat = .size16, numberOfShakes: CGFloat = 3, animatableData: CGFloat) {
        self.travelDistance = travelDistance
        self.numberOfShakes = numberOfShakes
        self.animatableData = animatableData
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = travelDistance * sin(animatableData * .pi * numberOfShakes)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

public extension View {
    /// Shakes horizontally once each time `trigger` changes — increment it under
    /// `withAnimation` (e.g. on a validation failure) to play a shake burst.
    func shake(trigger: CGFloat) -> some View {
        modifier(ShakeEffect(animatableData: trigger))
    }
}
