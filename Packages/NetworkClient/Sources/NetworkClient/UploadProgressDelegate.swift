import Foundation

/// Per-task delegate for `URLSession.upload(for:fromFile:delegate:)` that forwards fractional
/// send progress (0...1). Deliberately does not implement the auth-challenge method, so the
/// session-level `URLSessionAuthDelegate` still handles server-trust evaluation.
final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(min(1, max(0, fraction)))
    }
}
