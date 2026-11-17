@testable import CoreModels
import Testing

@Suite("VersionsSettings hourlyDays")
struct VersionsSettingsHourlyDaysTests {
    private struct Case: Sendable {
        let hourlyDays: Int
        let keepAllHours: Int
        let expected: Int
    }

    private static let cases = [
        Case(hourlyDays: 7, keepAllHours: 24, expected: 7),
        Case(hourlyDays: 1, keepAllHours: 24, expected: 1),
        Case(hourlyDays: 1, keepAllHours: 25, expected: 2),
        Case(hourlyDays: 1, keepAllHours: 48, expected: 2),
        Case(hourlyDays: 1, keepAllHours: 49, expected: 3),
        Case(hourlyDays: 3, keepAllHours: 720, expected: 30),
        Case(hourlyDays: 365, keepAllHours: 720, expected: 365),
        Case(hourlyDays: 1, keepAllHours: 1, expected: 1),
        Case(hourlyDays: 5, keepAllHours: 0, expected: 5),
    ]

    @Test("a shorter hourly span is raised to the whole days that keeping everything covers", arguments: cases)
    private func raisesToKeepAllDays(_ testCase: Case) {
        let raised = VersionsSettings.hourlyDays(testCase.hourlyDays, keepAllHours: testCase.keepAllHours)
        #expect(raised == testCase.expected)
    }
}
