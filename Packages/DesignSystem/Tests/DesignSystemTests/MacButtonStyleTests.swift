#if os(macOS)
    @testable import DesignSystem
    import SwiftUI
    import Testing

    @Suite("Mac button styles")
    struct MacButtonStyleTests {
        @Test("a destructive role turns a neutral button's label red, never a filled one's")
        func destructiveRoleColoursOnlyNeutralLabels() {
            #expect(DSButtonStyle.secondary.macForeground(isDestructive: true) == .negativeText)
            #expect(DSButtonStyle.secondary.macForeground(isDestructive: false) == .macChromeText)
            #expect(DSButtonStyle.primary.macForeground(isDestructive: true) == .onAccent)
            #expect(DSButtonStyle.failure.macForeground(isDestructive: true) == .white)
        }

        @Test("Mac buttons are shorter than the phone's and shrink with their size")
        func macHeightsFollowTheSize() {
            let heights = DSButtonSize.allCases.map(\.macHeight)
            #expect(heights == heights.sorted(by: >))
            #expect(zip(DSButtonSize.allCases, heights).allSatisfy { $1 < $0.height })
        }
    }
#endif
