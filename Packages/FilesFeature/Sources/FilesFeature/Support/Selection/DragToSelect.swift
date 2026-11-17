import DesignSystem
import SwiftUI
#if os(iOS)
    import UIKit.UIGestureRecognizerSubclass
#endif

/// Where the items of a list or grid sit on screen while it can be swept, in global coordinates, so the
/// slide can tell which item is under the finger. Not observed: rows write into it as they move and the
/// gesture reads it, with no view depending on it.
@MainActor
final class DragSelectFrames {
    private var frames: [String: CGRect] = [:]

    func set(_ frame: CGRect, for id: String) {
        frames[id] = frame
    }

    func remove(_ id: String) {
        frames[id] = nil
    }

    /// The item under `point`; nil over a gap, which keeps the item the finger was last over.
    func id(at point: CGPoint) -> String? {
        frames.first { $0.value.contains(point) }?.key
    }
}

extension EnvironmentValues {
    @Entry var dragSelectFrames: DragSelectFrames?
}

extension View {
    /// Select mode by sliding a finger across the items, as in Photos: a sideways start sweeps, an up
    /// or down start scrolls as usual, and holding the finger near the top or bottom edge scrolls on.
    /// `order` is the listing as shown; `onChange` receives each new selection.
    func dragToSelect(
        isEnabled: Bool,
        selection: Set<String>,
        order: @escaping () -> [String],
        onChange: @escaping (Set<String>) -> Void
    ) -> some View {
        modifier(DragToSelectModifier(isEnabled: isEnabled, selection: selection, order: order, onChange: onChange))
    }

    /// Marks one item of a `dragToSelect` list or grid, so a slide can find it.
    func dragSelectable(id: String) -> some View {
        modifier(DragSelectableModifier(id: id))
    }
}

private struct DragSelectableModifier: ViewModifier {
    let id: String
    @Environment(\.dragSelectFrames) private var frames

    func body(content: Content) -> some View {
        #if os(iOS)
            if let frames {
                content
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.set($0, for: id) }
                    .onDisappear { frames.remove(id) }
            } else {
                content
            }
        #else
            content
        #endif
    }
}

private struct DragToSelectModifier: ViewModifier {
    let isEnabled: Bool
    let selection: Set<String>
    let order: () -> [String]
    let onChange: (Set<String>) -> Void

    @State private var frames = DragSelectFrames()
    @State private var sweep: DragSelectionSweep?
    @State private var lastItemID: String?

    func body(content: Content) -> some View {
        #if os(iOS)
            content
                .environment(\.dragSelectFrames, frames)
                .gesture(DragSelectGesture(
                    isEnabled: isEnabled,
                    onBegan: begin,
                    onChanged: sweep(to:),
                    onEnded: {
                        sweep = nil
                        lastItemID = nil
                    }
                ))
                // Each item the slide picks up or lets go of ticks, like a picker's value changing.
                .hapticFeedback(.selection, trigger: selection) { _, _ in sweep != nil }
        #else
            content
        #endif
    }

    private func begin(at start: CGPoint, current: CGPoint) {
        guard let anchorID = frames.id(at: start) else { return }
        sweep = DragSelectionSweep(anchorID: anchorID, selection: selection)
        lastItemID = nil
        #if os(iOS)
            SlideToSelectTip.slideUsed()
        #endif
        sweep(to: current)
    }

    private func sweep(to point: CGPoint) {
        guard let sweep, let itemID = frames.id(at: point), itemID != lastItemID else { return }
        lastItemID = itemID
        let next = sweep.selection(order: order(), currentID: itemID)
        if next != selection {
            onChange(next)
        }
    }
}

#if os(iOS)
    private enum Constants {
        /// How far a touch moves before its direction decides between a sweep and a scroll.
        static let directionSlop: CGFloat = 8
        /// How close to the top or bottom edge the finger scrolls the list on.
        static let autoscrollBand: CGFloat = 72
        /// Points per second with the finger at the very edge.
        static let autoscrollMaxSpeed: CGFloat = 900
        /// A touch starting this close to the leading screen edge belongs to the system's back swipe.
        static let systemEdgeWidth: CGFloat = 24
    }

    private struct DragSelectGesture: UIGestureRecognizerRepresentable {
        let isEnabled: Bool
        let onBegan: (_ start: CGPoint, _ current: CGPoint) -> Void
        let onChanged: (CGPoint) -> Void
        let onEnded: () -> Void

        func makeUIGestureRecognizer(context _: Context) -> DragSelectPanRecognizer {
            let recognizer = DragSelectPanRecognizer()
            recognizer.maximumNumberOfTouches = 1
            recognizer.isEnabled = isEnabled
            return recognizer
        }

        func updateUIGestureRecognizer(_ recognizer: DragSelectPanRecognizer, context _: Context) {
            recognizer.isEnabled = isEnabled
        }

        func handleUIGestureRecognizerAction(_ recognizer: DragSelectPanRecognizer, context: Context) {
            let location = context.converter.location(in: .global)
            switch recognizer.state {
            case .began:
                let translation = context.converter.translation(in: .global) ?? .zero
                onBegan(CGPoint(x: location.x - translation.x, y: location.y - translation.y), location)
                recognizer.onAutoscroll = { onChanged(location) }
                recognizer.updateAutoscroll()
            case .changed:
                onChanged(location)
                // The finger rests while the list scrolls under it: the same spot meets the next item.
                recognizer.onAutoscroll = { onChanged(location) }
                recognizer.updateAutoscroll()
            case .ended, .cancelled, .failed:
                recognizer.stopAutoscroll()
                onEnded()
            default:
                break
            }
        }
    }

    /// A pan that only starts on a sideways move, so an up or down move still scrolls, and that the
    /// list's own scrolling waits on, so a sweep that turns vertical keeps selecting.
    final class DragSelectPanRecognizer: UIPanGestureRecognizer {
        var onAutoscroll: (() -> Void)?
        private weak var scrollView: UIScrollView?
        private var touchStart: CGPoint?
        private var displayLink: CADisplayLink?
        private var autoscrollSpeed: CGFloat = 0

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            if let touch = touches.first, let window = view?.window, startsAtSystemEdge(
                touch.location(in: window).x,
                window: window
            ) {
                state = .failed
                return
            }
            if touchStart == nil {
                touchStart = touches.first?.location(in: view)
            }
        }

        /// The leading edge in the layout direction: the right one in a right to left language.
        private func startsAtSystemEdge(_ x: CGFloat, window: UIWindow) -> Bool {
            let isRightToLeft = window.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let distance = isRightToLeft ? window.bounds.width - x : x
            return distance < Constants.systemEdgeWidth
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            if state == .possible, let touchStart, let point = touches.first?.location(in: view) {
                let horizontal = abs(point.x - touchStart.x)
                let vertical = abs(point.y - touchStart.y)
                if max(horizontal, vertical) >= Constants.directionSlop, vertical > horizontal {
                    state = .failed
                    return
                }
            }
            super.touchesMoved(touches, with: event)
        }

        override func reset() {
            super.reset()
            touchStart = nil
            stopAutoscroll()
            onAutoscroll = nil
        }

        override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if let scrollView = otherGestureRecognizer.view as? UIScrollView,
               otherGestureRecognizer === scrollView.panGestureRecognizer
            {
                // The innermost vertical scroller is the list itself, the one to scroll on near an edge.
                if self.scrollView == nil || scrollView.isDescendant(of: self.scrollView ?? scrollView) {
                    self.scrollView = scrollView
                }
                return true
            }
            return super.shouldBeRequiredToFail(by: otherGestureRecognizer)
        }

        /// Scrolls while the finger is held near the top or bottom of the visible list, faster the
        /// closer it gets to the edge.
        func updateAutoscroll() {
            guard let scrollView else { return }
            let visibleY = location(in: scrollView).y - scrollView.contentOffset.y
            let top = scrollView.adjustedContentInset.top + Constants.autoscrollBand
            let bottom = scrollView.bounds.height - scrollView.adjustedContentInset.bottom - Constants.autoscrollBand
            if visibleY < top {
                autoscrollSpeed = -Constants.autoscrollMaxSpeed * min(1, (top - visibleY) / Constants.autoscrollBand)
            } else if visibleY > bottom {
                autoscrollSpeed = Constants.autoscrollMaxSpeed * min(1, (visibleY - bottom) / Constants.autoscrollBand)
            } else {
                autoscrollSpeed = 0
            }
            if autoscrollSpeed == 0 {
                stopAutoscroll()
            } else if displayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(autoscrollTick(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        }

        func stopAutoscroll() {
            displayLink?.invalidate()
            displayLink = nil
            autoscrollSpeed = 0
        }

        @objc private func autoscrollTick(_ link: CADisplayLink) {
            guard let scrollView, state == .began || state == .changed else {
                stopAutoscroll()
                return
            }
            let minY = -scrollView.adjustedContentInset.top
            let maxY = max(
                minY,
                scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            )
            let elapsed = link.targetTimestamp - link.timestamp
            let next = min(maxY, max(minY, scrollView.contentOffset.y + autoscrollSpeed * elapsed))
            guard next != scrollView.contentOffset.y else { return }
            scrollView.contentOffset.y = next
            onAutoscroll?()
        }
    }
#endif
