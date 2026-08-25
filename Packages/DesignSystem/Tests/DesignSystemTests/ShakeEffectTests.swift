import SwiftUI
import Testing
@testable import DesignSystem

@Suite("ShakeEffect")
struct ShakeEffectTests {
    // `ProjectionTransform.m31`/`m32` hold the affine translation (tx/ty) components —
    // there's no `.tx`/`.ty` accessor directly on `ProjectionTransform`.

    @Test("zero animatableData produces no translation")
    func atRest() {
        let effect = ShakeEffect(travelDistance: 10, numberOfShakes: 3, animatableData: 0)
        let transform = effect.effectValue(size: CGSize(width: 100, height: 40))
        #expect(transform.m31 == 0)
        #expect(transform.m32 == 0)
    }

    @Test("animatableData of 1 completes a whole number of oscillations back to zero translation")
    func fullCycleReturnsToRest() {
        // sin(1 * pi * numberOfShakes) is 0 whenever numberOfShakes is an integer, so a
        // full burst should always end back at zero translation regardless of shake count.
        let effect = ShakeEffect(travelDistance: 16, numberOfShakes: 3, animatableData: 1)
        let transform = effect.effectValue(size: CGSize(width: 100, height: 40))
        #expect(abs(transform.m31) < 0.0001)
    }

    @Test("larger travelDistance scales the peak translation proportionally")
    func travelDistanceScalesTranslation() {
        let small = ShakeEffect(travelDistance: 8, numberOfShakes: 3, animatableData: 0.5 / 3)
        let large = ShakeEffect(travelDistance: 16, numberOfShakes: 3, animatableData: 0.5 / 3)
        let smallTx = small.effectValue(size: .zero).m31
        let largeTx = large.effectValue(size: .zero).m31
        #expect(largeTx == smallTx * 2)
    }

    @Test("negative animatableData mirrors the translation direction")
    func negativeInputMirrors() {
        let positive = ShakeEffect(travelDistance: 10, numberOfShakes: 3, animatableData: 1.0 / 6)
        let negative = ShakeEffect(travelDistance: 10, numberOfShakes: 3, animatableData: -1.0 / 6)
        let positiveTx = positive.effectValue(size: .zero).m31
        let negativeTx = negative.effectValue(size: .zero).m31
        #expect(abs(positiveTx + negativeTx) < 0.0001)
    }
}
