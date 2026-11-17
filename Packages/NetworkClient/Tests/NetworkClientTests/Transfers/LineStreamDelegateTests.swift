import Foundation
@testable import NetworkClient
import Testing

@Suite("LineStreamDelegate")
struct LineStreamDelegateTests {
    private enum Constants {
        static let url = URL(string: "https://files.example.com/stream")!
        static let maxBytes = 64
    }

    private let session = URLSession(configuration: .ephemeral)

    private func delegate(
        lines: LockIsolatedBox<[String]>,
        result: LockIsolatedBox<Result<Data, Error>?>
    ) -> LineStreamDelegate {
        LineStreamDelegate(
            maxBytes: Constants.maxBytes,
            onLine: { line in lines.withValue { $0.append(String(decoding: line, as: UTF8.self)) } },
            finish: { outcome in result.withValue { $0 = outcome.map(\.0) } }
        )
    }

    @Test("A line split across two chunks is reported once, whole, and the body is kept")
    func joinsSplitLines() throws {
        let lines = LockIsolatedBox<[String]>([])
        let result = LockIsolatedBox<Result<Data, Error>?>(nil)
        let delegate = delegate(lines: lines, result: result)
        let task = session.dataTask(with: Constants.url)

        delegate.urlSession(session, dataTask: task, didReceive: Data("first\nsec".utf8))
        delegate.urlSession(session, dataTask: task, didReceive: Data("ond\n".utf8))
        delegate.urlSession(session, task: task, didCompleteWithError: nil)

        #expect(lines.value == ["first", "second"])
        let body = try #require(try result.value?.get())
        #expect(String(decoding: body, as: UTF8.self) == "first\nsecond\n")
    }

    @Test("A body over the cap stops reading and ends as too large")
    func stopsAtTheCap() {
        let lines = LockIsolatedBox<[String]>([])
        let result = LockIsolatedBox<Result<Data, Error>?>(nil)
        let delegate = delegate(lines: lines, result: result)
        let task = session.dataTask(with: Constants.url)

        delegate.urlSession(
            session,
            dataTask: task,
            didReceive: Data(repeating: UInt8(ascii: "x"), count: Constants.maxBytes + 1)
        )
        delegate.urlSession(session, dataTask: task, didReceive: Data("late\n".utf8))
        delegate.urlSession(session, task: task, didCompleteWithError: nil)

        #expect(lines.value.isEmpty)
        guard case let .failure(error) = result.value else {
            Issue.record("Expected the read to fail")
            return
        }
        #expect(error as? NetworkError == .responseTooLarge)
    }
}
