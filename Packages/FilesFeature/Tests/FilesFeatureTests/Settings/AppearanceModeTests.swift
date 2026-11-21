@testable import FilesFeature
import SwiftUI
import Testing

struct AppearanceModeTests {
    struct StoredChoice: Sendable {
        let hasOverride: Bool
        let isDark: Bool
        let expected: AppearanceMode
    }

    nonisolated static let storedChoices = [
        StoredChoice(hasOverride: false, isDark: false, expected: .system),
        StoredChoice(hasOverride: false, isDark: true, expected: .system),
        StoredChoice(hasOverride: true, isDark: false, expected: .light),
        StoredChoice(hasOverride: true, isDark: true, expected: .dark),
    ]

    @Test(arguments: storedChoices)
    func theTwoLegacyKeysDecodeToTheMode(_ choice: StoredChoice) {
        #expect(AppearanceMode(hasOverride: choice.hasOverride, isDark: choice.isDark) == choice.expected)
    }

    @Test(arguments: AppearanceMode.allCases)
    func aModeSurvivesBeingStoredAsTheTwoKeysAndReadBack(_ mode: AppearanceMode) {
        #expect(AppearanceMode(hasOverride: mode.hasOverride, isDark: mode.isDark) == mode)
    }

    @Test
    func onlyDarkPrefersDarkAndOnlySystemHasNoOverride() {
        #expect(AppearanceMode.allCases.filter(\.isDark) == [.dark])
        #expect(AppearanceMode.allCases.filter { !$0.hasOverride } == [.system])
    }

    @Test
    func systemLeavesTheColorSchemeToTheDevice() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }
}
