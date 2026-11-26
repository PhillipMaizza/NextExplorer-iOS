#if os(macOS)
    @testable import DesignSystem
    import SwiftUI
    import Testing

    @Suite("Mac text scale")
    struct MacTextScaleTests {
        @Test("the scale stays inside its range")
        func scaleIsClamped() {
            #expect(MacTextScale.clamped(0.5) == MacTextScale.range.lowerBound)
            #expect(MacTextScale.clamped(3) == MacTextScale.range.upperBound)
            #expect(MacTextScale.clamped(1.2) == 1.2)
        }

        @Test("body text grows with the scale")
        func bodyTextScales() {
            let body = Typography.TextType.body2(.regular)
            #expect(body.macPointSize(scale: 1) == 13)
            #expect(body.macPointSize(scale: 1.4) == 13 * 1.4)
        }

        @Test("large titles stop growing at the largest scaled size")
        func largeTitlesAreCapped() {
            #expect(Typography.TextType.display.macPointSize(scale: 1.4) == Typography.TextType.display
                .macPointSize(scale: 1))
            #expect(Typography.TextType.headline1.macPointSize(scale: 1.4) == MacTextScale.largestScaledPointSize)
        }

        @Test("native controls step up in size as the text grows")
        func nativeControlsFollowTheScale() {
            #expect(MacTextScale.controlSize(1) == .regular)
            #expect(MacTextScale.controlSize(1.2) == .large)
            #expect(MacTextScale.controlSize(1.4) == .extraLarge)
        }

        @Test("control heights grow with the text and keep their order")
        func controlHeightsScale() {
            let heights = MacControlHeight.allCases.map(\.points)
            #expect(heights == heights.sorted())
            #expect(MacControlHeight.regular.points(scale: 1.4) == MacControlHeight.regular.points * 1.4)
        }
    }
#endif
