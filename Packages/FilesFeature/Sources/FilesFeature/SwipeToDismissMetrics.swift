import CoreGraphics

/// The Photos-style "drag the full-screen content vertically to dismiss" interaction is used
/// by the image gallery, the streaming player and the in-archive image viewer. They each wire
/// the gesture into their own view tree, but the thresholds and the offset → dim/shrink/fade
/// math are identical — kept here once rather than as three copies of the same constants.
enum SwipeToDismissMetrics {
    /// Vertical drag distance past which releasing dismisses.
    static let distanceThreshold: CGFloat = 120
    /// Projected fling distance that dismisses even on a short, fast flick.
    static let predictedThreshold: CGFloat = 360
    /// Only track a drag as a dismiss once it is clearly more vertical than horizontal.
    static let minimumDragDistance: CGFloat = 12
    static let minBackgroundOpacity: Double = 0.35
    static let scaleFloor: CGFloat = 0.88
    static let scaleDivisor: CGFloat = 1400
    static let resetSpringResponse: Double = 0.3
    static let resetSpringDamping: Double = 0.85
    /// Fade the frozen content + dimmed backdrop to nothing on release-to-dismiss, then pull
    /// the cover with animations off, so the exit is a clean crossfade rather than our motion
    /// fighting the cover's own slide.
    static let dismissFadeDuration: Double = 0.2
    /// Content opacity at full drag progress, before release.
    static let draggingContentOpacityFloor: Double = 0.6

    static func progress(forOffset offset: CGFloat) -> CGFloat {
        min(1, abs(offset) / distanceThreshold)
    }

    static func backgroundOpacity(forOffset offset: CGFloat, isDismissing: Bool) -> Double {
        isDismissing ? 0 : 1 - (1 - minBackgroundOpacity) * Double(progress(forOffset: offset))
    }

    static func contentOpacity(forOffset offset: CGFloat, isDismissing: Bool) -> Double {
        isDismissing ? 0 : 1 - (1 - draggingContentOpacityFloor) * Double(progress(forOffset: offset))
    }

    static func scale(forOffset offset: CGFloat) -> CGFloat {
        max(scaleFloor, 1 - abs(offset) / scaleDivisor)
    }

    /// Whether a released drag should dismiss: far enough, or flicked hard enough.
    static func shouldDismiss(translationHeight: CGFloat, predictedHeight: CGFloat) -> Bool {
        abs(translationHeight) > distanceThreshold || abs(predictedHeight) > predictedThreshold
    }
}
