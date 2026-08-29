import AppStorageKeys
import SwiftUI

private struct HapticFeedbackModifier<T: Equatable>: ViewModifier {
    /// Mirrors the same key `SettingsView`'s "Haptics" toggle writes — read live here
    /// rather than threaded through the environment, so every call site stays a plain
    /// one-line modifier.
    @AppStorage(AppStorageKeys.hapticsEnabled) private var isHapticsEnabled = true

    let feedback: SensoryFeedback
    let trigger: T
    let condition: (T, T) -> Bool

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { oldValue, newValue in
            isHapticsEnabled && condition(oldValue, newValue)
        }
    }
}

public extension View {
    /// Drop-in replacement for `.sensoryFeedback(_:trigger:)` that additionally respects the
    /// user's "Haptics" setting — every haptic in the app should go through this, never the
    /// raw SwiftUI modifier directly, or it'll keep buzzing after the user turns them off.
    func hapticFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        modifier(HapticFeedbackModifier(feedback: feedback, trigger: trigger, condition: { _, _ in true }))
    }

    /// As above, but only plays when `condition` returns true for the old/new trigger value —
    /// mirrors `.sensoryFeedback(_:trigger:condition:)`.
    func hapticFeedback<T: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: T,
        condition: @escaping (T, T) -> Bool
    ) -> some View {
        modifier(HapticFeedbackModifier(feedback: feedback, trigger: trigger, condition: condition))
    }
}
