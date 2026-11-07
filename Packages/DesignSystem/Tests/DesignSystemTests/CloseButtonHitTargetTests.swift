@testable import DesignSystem
import SwiftUI
import Testing

#if !os(macOS)
    @MainActor
    @Suite("Close button hit target")
    struct CloseButtonHitTargetTests {
        private func renderedSize(_ view: some View) -> CGSize? {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            return renderer.uiImage?.size
        }

        @Test("the minimum hit target is the 44pt touch minimum")
        func minimumIsFortyFour() {
            #expect(DSHitTarget.minimumSize == 44)
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
