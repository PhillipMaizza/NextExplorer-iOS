@testable import DesignSystem
import Testing

@Suite("MorphingButtonChrome")
struct MorphingButtonChromeTests {
    @Test("progress 0 is the fully expanded rectangle")
    func expanded() {
        let width = MorphingButtonChrome.width(progress: 0, expandedWidth: 300, height: 56)
        let radius = MorphingButtonChrome.radius(progress: 0, height: 56)
        #expect(width == 300)
        #expect(radius == .radiusControl)
    }

    @Test("progress 1 is the fully collapsed circle")
    func collapsed() {
        let width = MorphingButtonChrome.width(progress: 1, expandedWidth: 300, height: 56)
        let radius = MorphingButtonChrome.radius(progress: 1, height: 56)
        #expect(width == 56)
        #expect(radius == 28)
    }

    @Test("intermediate progress interpolates linearly between the two extremes")
    func midpoint() {
        let width = MorphingButtonChrome.width(progress: 0.5, expandedWidth: 300, height: 56)
        let radius = MorphingButtonChrome.radius(progress: 0.5, height: 56)
        #expect(width == 178)
        #expect(radius == (.radiusControl + 28) / 2)
    }

    @Test("expandedWidth smaller than height still collapses to exactly height")
    func expandedNarrowerThanHeight() {
        // Edge case: a very narrow button (expandedWidth < height) should still land
        // exactly on `height` at progress 1, not undershoot/overshoot from the lerp.
        let width = MorphingButtonChrome.width(progress: 1, expandedWidth: 40, height: 56)
        #expect(width == 56)
    }
}
