import Foundation

/// Per task delegate for a response read as it arrives: keeps the chunks, hands each complete line to
/// `onLine`, and reports the whole body (capped at `maxBytes`) once the task ends. It does not
/// implement the auth challenge method, so the session's `URLSessionAuthDelegate` still handles trust.
final class LineStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let onLine: @Sendable (Data) -> Void
    private let maxBytes: Int
    private let finish: @Sendable (Result<(Data, URLResponse?), Error>) -> Void
    private var body = Data()
    private var lineStart = 0
    private var isTooLarge = false

    init(
        maxBytes: Int,
        onLine: @escaping @Sendable (Data) -> Void,
        finish: @escaping @Sendable (Result<(Data, URLResponse?), Error>) -> Void
    ) {
        self.maxBytes = maxBytes
        self.onLine = onLine
        self.finish = finish
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !isTooLarge else { return }
        body.append(data)
        guard body.count <= maxBytes else {
            isTooLarge = true
            dataTask.cancel()
            return
        }
        while let newline = body[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
            onLine(Data(body[lineStart ..< newline]))
            lineStart = newline + 1
        }
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let body = body
        let isTooLarge = isTooLarge
        lock.unlock()
        if isTooLarge {
            finish(.failure(NetworkError.responseTooLarge))
        } else if let error {
            finish(.failure(error))
        } else {
            finish(.success((body, task.response)))
        }
    }
}
