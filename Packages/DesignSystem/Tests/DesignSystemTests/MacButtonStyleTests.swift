#if os(macOS)
    @testable import DesignSystem
    import SwiftUI
    import Testing

    @Suite("Mac button styles")
    struct MacButtonStyleTests {
        @Test("a destructive role turns a neutral button's label red, never a filled one's")
        func destructiveRoleColoursOnlyNeutralLabels() {
            #expect(DSButtonStyle.secondary.macForeground(isDestructive: true, tone: .neutral) == .negativeText)
            #expect(DSButtonStyle.secondary.macForeground(isDestructive: false, tone: .neutral) == .macChromeText)
            #expect(DSButtonStyle.primary.macForeground(isDestructive: true, tone: .neutral) == .onAccent)
            #expect(DSButtonStyle.failure.macForeground(isDestructive: true, tone: .neutral) == .white)
        }

        @Test("an outline button takes its tone's colour, and a destructive role overrides it")
        func outlineToneColoursTheLabelAndBorder() {
            #expect(DSButtonStyle.outline.macForeground(isDestructive: false, tone: .success) == .positiveText)
            #expect(DSButtonStyle.outline.macForeground(isDestructive: true, tone: .success) == .negativeText)
            #expect(DSButtonStyle.outline.macBorder(isDestructive: false, tone: .neutral) == .macChromeDisabled)
            #expect(DSButtonStyle.secondary.macBorder(isDestructive: false, tone: .success) == .clear)
        }

        @Test("Mac buttons are shorter than the phone's and shrink with their size")
        func macHeightsFollowTheSize() {
            let heights = DSButtonSize.allCases.map(\.macHeight.points)
            #expect(heights == heights.sorted(by: >))
            #expect(zip(DSButtonSize.allCases, heights).allSatisfy { $1 < $0.height })
        }
    }
#endif
