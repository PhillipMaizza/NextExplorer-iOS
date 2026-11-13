@testable import DesignSystem
import SwiftUI
import Testing

#if !os(macOS)
    private final class AppliedBox: @unchecked Sendable {
        var isApplied = false
    }

    @MainActor
    @Suite("Close button hit target")
    struct CloseButtonHitTargetTests {
        /// Lays the view out in a window and reads whether `dsMinimumHitTarget` is in its body.
        private func appliesHitTarget(_ view: some View) -> Bool {
            let box = AppliedBox()
            let host = UIHostingController(rootView: view
                .onPreferenceChange(DSHitTargetAppliedKey.self) { box.isApplied = $0 })
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            return box.isApplied
        }

        @Test("a control without the modifier is reported as not having the hit target")
        func probeSeesAControlWithoutIt() {
            #expect(!appliesHitTarget(Color.red.frame(width: 28, height: 28)))
        }

        @Test("a control with the modifier is reported as having the hit target")
        func probeSeesAControlWithIt() {
            #expect(appliesHitTarget(Color.red.frame(width: 28, height: 28).dsMinimumHitTarget()))
        }

        @Test("DSCloseButton applies the hit target")
        func closeButtonAppliesIt() {
            #expect(appliesHitTarget(DSCloseButton(action: {})))
        }

        @Test("DSSheetHeader applies the hit target to its close button")
        func sheetHeaderAppliesIt() {
            #expect(appliesHitTarget(DSSheetHeader(
                icon: IconKit.close,
                title: nil,
                closeAccessibilityLabel: "Close",
                onClose: {}
            )))
        }

        private func renderedSize(_ view: some View) -> CGSize? {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            return renderer.uiImage?.size
        }

        @Test("the hit area reaches 44 points on every side of a small control and nothing past a large one")
        func expansionFillsUpToTheMinimum() {
            let small = DSHitTarget.expansion(for: CGSize(width: 28, height: 20))
            #expect(28 + 2 * small.width == DSHitTarget.minimumSize)
            #expect(20 + 2 * small.height == DSHitTarget.minimumSize)
            #expect(DSHitTarget.expansion(for: CGSize(width: 80, height: 44)) == .zero)
            #expect(DSHitTarget.expansion(for: .zero) == CGSize(width: 22, height: 22))
        }

        @Test("the modifier never changes the layout size of a small or a large control")
        func modifierLeavesLayoutAlone() throws {
            let smallBefore = try #require(renderedSize(Color.red.frame(width: 28, height: 28)))
            let smallAfter = try #require(renderedSize(Color.red.frame(width: 28, height: 28).dsMinimumHitTarget()))
            #expect(smallAfter == smallBefore)
            let large = try #require(renderedSize(Color.red.frame(width: 80, height: 60).dsMinimumHitTarget()))
            #expect(large.width == 80 && large.height == 60)
        }

        @Test("DSCloseButton keeps the layout size it had before the hit target was added")
        func closeButtonLayoutIsUnchanged() throws {
            let button = try #require(renderedSize(DSCloseButton(action: {})))
            let side = CGFloat.iconXSmall + 2 * CGFloat.space8
            #expect(side < DSHitTarget.minimumSize)
            #expect(button == CGSize(width: side, height: side))
        }
    }
#endif
