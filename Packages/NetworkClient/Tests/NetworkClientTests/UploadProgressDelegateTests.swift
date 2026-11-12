import Foundation
@testable import NetworkClient
import Testing
import TestUtils

@Suite("UploadProgressDelegate")
struct UploadProgressDelegateTests {
    private struct Case: Sendable, CustomTestStringConvertible {
        let sent: Int64
        let expected: Int64
        let fraction: Double?

        var testDescription: String {
            "\(sent) of \(expected)"
        }
    }

    private static let cases = [
        Case(sent: 50, expected: 200, fraction: 0.25),
        Case(sent: 0, expected: 100, fraction: 0),
        Case(sent: 100, expected: 100, fraction: 1),
        Case(sent: 150, expected: 100, fraction: 1),
        Case(sent: -5, expected: 100, fraction: 0),
        Case(sent: 10, expected: 0, fraction: nil),
        Case(sent: 10, expected: NSURLSessionTransferSizeUnknown, fraction: nil),
    ]

    @Test("the reported fraction is clamped to 0...1 and nothing is reported without a known total", arguments: cases)
    private func reportsClampedFraction(_ testCase: Case) {
        let reports = LockIsolatedBox<[Double]>([])
        let delegate = UploadProgressDelegate { fraction in
            reports.withValue { $0.append(fraction) }
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: TestHost.serverURL)

        delegate.urlSession(session, task: task, didSendBodyData: 0, totalBytesSent: testCase.sent, totalBytesExpectedToSend: testCase.expected)

        #expect(reports.value == testCase.fraction.map { [$0] } ?? [])
    }

    @Test("every chunk is reported in order")
    func reportsEveryChunk() {
        let reports = LockIsolatedBox<[Double]>([])
        let delegate = UploadProgressDelegate { fraction in
            reports.withValue { $0.append(fraction) }
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: TestHost.serverURL)

        for sent: Int64 in [25, 50, 100] {
            delegate.urlSession(session, task: task, didSendBodyData: 25, totalBytesSent: sent, totalBytesExpectedToSend: 100)
        }

        #expect(reports.value == [0.25, 0.5, 1])
    }
}
