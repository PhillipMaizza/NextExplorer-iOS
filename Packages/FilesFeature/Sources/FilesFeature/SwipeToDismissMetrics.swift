import SwiftUI

/// Photos-style "drag the full-screen content vertically to dismiss". The browse-tab media
/// previews get this natively from the `.zoom` navigation transition (see
/// `BrowseContentView`'s `matchedTransitionSource` / `navigationTransition`). This manual
/// version — `swipeToDismissContent` below, plus the offset → dim/shrink/fade math here — is
/// the fallback for viewers presented without a `.zoom` source: the in-archive entry previews,
/// which are an in-view overlay rather than a cover.
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

extension View {
    /// Vertical drag-to-dismiss for a full-screen media cover: the whole viewer (chrome
    /// included) follows the finger against a black backdrop as it is dragged either
    /// direction, dimming and shrinking as it goes, then springs back if released short or
    /// crossfades out and calls `onDismiss` once the drag passes the threshold. `isSuspended`
    /// freezes the gesture while the content itself is panning (a magnified image), so panning
    /// never closes the viewer.
    func swipeToDismissContent(isSuspended: Bool = false, onDismiss: @escaping () -> Void) -> some View {
        modifier(SwipeToDismissContent(isSuspended: isSuspended, onDismiss: onDismiss))
    }
}

private struct SwipeToDismissContent: ViewModifier {
    let isSuspended: Bool
    let onDismiss: () -> Void

    /// Live vertical translation of an in-progress dismiss drag (0 when idle).
    @State private var dragOffset: CGFloat = 0
    /// Set once a drag crosses the threshold: fades content + backdrop to 0 as the cover goes.
    @State private var isDismissing = false

    func body(content: Content) -> some View {
        ZStack {
            Color.black
                .opacity(SwipeToDismissMetrics.backgroundOpacity(forOffset: dragOffset, isDismissing: isDismissing))
                .ignoresSafeArea()

            content
                .scaleEffect(SwipeToDismissMetrics.scale(forOffset: dragOffset))
                .offset(y: dragOffset)
                .opacity(SwipeToDismissMetrics.contentOpacity(forOffset: dragOffset, isDismissing: isDismissing))
        }
        .simultaneousGesture(dismissDrag)
    }

    /// Vertical swipe (either direction) — runs alongside any horizontal paging/scrubber and
    /// the zoom scroll view's own pan, which keep their gestures.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: SwipeToDismissMetrics.minimumDragDistance)
            .onChanged { value in
                guard !isSuspended, !isDismissing,
                      abs(value.translation.height) > abs(value.translation.width) else {
                    dragOffset = 0
                    return
                }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard !isSuspended, abs(value.translation.height) > abs(value.translation.width) else {
                    dragOffset = 0
                    return
                }
                if SwipeToDismissMetrics.shouldDismiss(
                    translationHeight: value.translation.height,
                    predictedHeight: value.predictedEndTranslation.height
                ) {
                    // Freeze the content where the finger left it and crossfade it out, then
                    // remove the cover with animations off — no fly-out to collide with the
                    // fullScreenCover's own slide.
                    withAnimation(.easeOut(duration: SwipeToDismissMetrics.dismissFadeDuration)) {
                        isDismissing = true
                    } completion: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { onDismiss() }
                    }
                } else {
                    withAnimation(.spring(
                        response: SwipeToDismissMetrics.resetSpringResponse,
                        dampingFraction: SwipeToDismissMetrics.resetSpringDamping
                    )) {
                        dragOffset = 0
                    }
                }
            }
    }
}
