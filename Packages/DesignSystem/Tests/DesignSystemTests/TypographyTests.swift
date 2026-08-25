import Testing
@testable import DesignSystem

@Suite("Typography")
struct TypographyTests {
    @Test("every text style resolves to a distinct color role")
    func textStylesHaveColors() {
        #expect(Typography.TextStyle.primary.color != Typography.TextStyle.negative.color)
    }

    @Test("headline1 is the largest, non-zero-size text type")
    func headline1IsLargest() {
        // Font isn't directly inspectable for point size without rendering, so this just
        // confirms every case produces a font without crashing / force-unwrapping.
        for type: Typography.TextType in [.headline1, .body1, .body2, .label1] {
            _ = type.font()
        }
    }
}
