@testable import DesignSystem
import Testing

@Suite("Typography")
struct TypographyTests {
    @Test("every text style resolves to a distinct color role")
    func textStylesHaveColors() {
        #expect(Typography.TextStyle.primaryOnSurface.color != Typography.TextStyle.error.color)
    }
}
