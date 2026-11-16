@testable import DesignSystem
import SwiftUI
import Testing

@Suite("Typography")
struct TypographyTests {
    /// Links, errors and successes carry meaning in their color, so they use the text tokens tuned
    /// for contrast (WCAG AA), never the brighter fill colors of the same hue.
    @Test("text that carries meaning uses the contrast safe text tokens")
    func meaningfulStylesUseTheTextTokens() {
        #expect(Typography.TextStyle.link.color == Color.accentText)
        #expect(Typography.TextStyle.error.color == Color.negativeText)
        #expect(Typography.TextStyle.success.color == Color.positiveText)
    }

    @Test("an error never reads as plain primary text")
    func errorStandsOutFromPrimary() {
        #expect(Typography.TextStyle.primaryOnSurface.color != Typography.TextStyle.error.color)
    }
}
