@testable import FilesFeature
import SwiftUI
import Testing

struct AppearanceModeTests {
    struct StoredChoice: Sendable {
        let hasOverride: Bool
        let prefersDark: Bool
        let expected: AppearanceMode
    }

    nonisolated static let storedChoices = [
        StoredChoice(hasOverride: false, prefersDark: false, expected: .system),
        StoredChoice(hasOverride: false, prefersDark: true, expected: .system),
        StoredChoice(hasOverride: true, prefersDark: false, expected: .light),
        StoredChoice(hasOverride: true, prefersDark: true, expected: .dark),
    ]

    @Test(arguments: storedChoices)
    func theTwoLegacyKeysDecodeToTheMode(_ choice: StoredChoice) {
        #expect(AppearanceMode(hasOverride: choice.hasOverride, prefersDark: choice.prefersDark) == choice.expected)
    }

    @Test(arguments: AppearanceMode.allCases)
    func aModeSurvivesBeingStoredAsTheTwoKeysAndReadBack(_ mode: AppearanceMode) {
        #expect(AppearanceMode(hasOverride: mode.hasOverride, prefersDark: mode.prefersDark) == mode)
    }

    @Test
    func onlyDarkPrefersDarkAndOnlySystemHasNoOverride() {
        #expect(AppearanceMode.allCases.filter(\.prefersDark) == [.dark])
        #expect(AppearanceMode.allCases.filter { !$0.hasOverride } == [.system])
    }

    @Test
    func systemLeavesTheColorSchemeToTheDevice() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }
}
