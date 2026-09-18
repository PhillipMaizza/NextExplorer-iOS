@preconcurrency import ImageIO
import UIKit

/// Streams a remote image and yields it at rising quality, so a large photo fades from rough to
/// sharp instead of blanking behind a spinner. Bytes arrive in chunks on a background delegate queue
/// (never the per byte `URLSession.bytes` loop rule 28 forbids) and feed an incremental
/// `CGImageSource`; each emitted frame is a thumbnail capped at `maxPixelDimension`, so memory stays
/// bounded even though the source file itself streams in whole. All decoding is off the main actor.
enum ProgressiveImageLoader {
    private enum Constants {
        /// Bounds a stalled request so a page swiped away mid load doesn't leave a socket open (see
        /// `frames`).
        static let requestTimeout: TimeInterval = 30
        /// New bytes to accumulate before decoding another progressively sharper frame.
        static let emitThreshold = 96 * 1024
        /// Hard ceiling on the accumulated response, matching `NetworkClient`'s in memory cap.
        static let maxResponseBytes = 32 * 1024 * 1024
    }

    /// Emits successively sharper frames for `url`, then finishes. Finishing with no frames means the
    /// request failed (or was cancelled); the caller keeps its low quality placeholder and, if it was
    /// a real failure, surfaces its error state.
    static func frames(url: URL, cookies: [HTTPCookie], maxPixelDimension: CGFloat) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            let delegate = Delegate(maxPixelDimension: maxPixelDimension, continuation: continuation)
            let configuration = URLSessionConfiguration.ephemeral
            // Bound a stalled request: `AsyncStream.next()` isn't cancellation aware, so a page
            // swiped away mid load only tears the session down on the next chunk or on completion;
            // a timeout guarantees that happens rather than a socket lingering indefinitely.
            configuration.timeoutIntervalForRequest = Constants.requestTimeout
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            var request = URLRequest(url: url)
            for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                request.setValue(value, forHTTPHeaderField: field)
            }
            let task = session.dataTask(with: request)
            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
            task.resume()
        }
    }

    /// `@unchecked Sendable`: `URLSession` requires a `Sendable` delegate, and every stored property
    /// here is read and written only from the session's serial delegate queue (created because
    /// `delegateQueue` is `nil`), so the mutable state and the non `Sendable` `CGImageSource` are
    /// never touched concurrently.
    private final class Delegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let maxPixelDimension: CGFloat
        private let continuation: AsyncStream<UIImage>.Continuation
        private let source = CGImageSourceCreateIncremental(nil)
        private var buffer = Data()
        /// New bytes since the last decode, throttled so a big file doesn't decode a thumbnail on
        /// every small chunk.
        private var bytesSinceLastEmit = 0
        private var didFail = false

        init(maxPixelDimension: CGFloat, continuation: AsyncStream<UIImage>.Continuation) {
            self.maxPixelDimension = maxPixelDimension
            self.continuation = continuation
        }

        func urlSession(
            _: URLSession, dataTask _: URLSessionDataTask, didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            if let http = response as? HTTPURLResponse, !(200 ..< 300 ~= http.statusCode) {
                didFail = true
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        }

        func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
            buffer.append(data)
            guard buffer.count <= Constants.maxResponseBytes else {
                didFail = true
                continuation.finish()
                return
            }
            CGImageSourceUpdateData(source, buffer as CFData, false)
            bytesSinceLastEmit += data.count
            if bytesSinceLastEmit >= Constants.emitThreshold {
                bytesSinceLastEmit = 0
                emitThumbnail()
            }
        }

        func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
            if error != nil || didFail {
                continuation.finish()
                return
            }
            CGImageSourceUpdateData(source, buffer as CFData, true)
            emitThumbnail()
            continuation.finish()
        }

        /// Decode the highest quality frame the bytes received so far allow, capped to
        /// `maxPixelDimension`. A partially loaded progressive JPEG still yields a coarse image here.
        private func emitThumbnail() {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return
            }
            continuation.yield(UIImage(cgImage: cgImage))
        }
    }
}
