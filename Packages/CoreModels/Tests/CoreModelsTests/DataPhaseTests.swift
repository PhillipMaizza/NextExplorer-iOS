@testable import CoreModels
import Testing
import TestUtils

@Suite("DataPhase")
struct DataPhaseTests {
    private struct Case: Sendable, CustomTestStringConvertible {
        let phase: DataPhase
        let hasLoaded: Bool
        let errorMessage: String?
        let shouldLoadOnAppear: Bool

        var testDescription: String {
            "\(phase)"
        }
    }

    private static let cases = [
        Case(phase: .idle, hasLoaded: false, errorMessage: nil, shouldLoadOnAppear: true),
        Case(phase: .loading, hasLoaded: false, errorMessage: nil, shouldLoadOnAppear: false),
        Case(phase: .loaded, hasLoaded: true, errorMessage: nil, shouldLoadOnAppear: false),
        Case(phase: .failed(TestFailure.offline), hasLoaded: true, errorMessage: TestFailure.offline, shouldLoadOnAppear: true),
        Case(phase: .failed(""), hasLoaded: true, errorMessage: "", shouldLoadOnAppear: true),
    ]

    @Test("each phase derives hasLoaded, errorMessage and shouldLoadOnAppear", arguments: cases)
    private func derivesFlags(_ testCase: Case) {
        #expect(testCase.phase.hasLoaded == testCase.hasLoaded)
        #expect(testCase.phase.errorMessage == testCase.errorMessage)
        #expect(testCase.phase.shouldLoadOnAppear == testCase.shouldLoadOnAppear)
    }

}
