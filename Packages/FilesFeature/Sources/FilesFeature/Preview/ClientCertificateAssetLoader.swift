import AVFoundation
import Foundation
import NetworkClient
import UniformTypeIdentifiers

/// Streams a remote media file for `AVPlayer` when its server wants a TLS client certificate.
/// AVFoundation's own HTTP stack never answers that challenge, so the asset gets a private URL
/// scheme and every range AVPlayer asks for is fetched here instead, through a session that
/// presents the certificate. Bytes go straight to the loading request as they arrive, so memory
/// stays flat and seeking still works.
///
/// `@unchecked Sendable`: all mutable state is touched only on `queue`, which is both the resource
/// loader's delegate queue and the underlying queue of the session's delegate queue.
final class ClientCertificateAssetLoader: NSObject, @unchecked Sendable {
    static let scheme = "nxmtls"

    private struct Pending {
        let loadingRequest: AVAssetResourceLoadingRequest
        /// Bytes to drop before answering, when the server ignored the Range header and sent the
        /// whole file for a request that starts later.
        var bytesToSkip: Int64
        let requestedOffset: Int64
    }

    let asset: AVURLAsset
    private let remoteURL: URL
    private let cookies: [HTTPCookie]
    private let fileExtension: String
    private let queue = DispatchQueue(label: "ClientCertificateAssetLoader")
    private var session: URLSession?
    private var pending: [Int: Pending] = [:]

    init?(remoteURL: URL, cookies: [HTTPCookie], fileExtension: String) {
        guard var components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false), components.scheme == "https" else {
            return nil
        }
        components.scheme = Self.scheme
        guard let loaderURL = components.url else { return nil }
        self.remoteURL = remoteURL
        self.cookies = cookies
        self.fileExtension = fileExtension
        asset = AVURLAsset(url: loaderURL)
        super.init()
        asset.resourceLoader.setDelegate(self, queue: queue)
    }

    /// Ends every transfer and breaks the session's hold on this loader. Call when the player
    /// goes away.
    func invalidate() {
        queue.async { [self] in
            session?.invalidateAndCancel()
            session = nil
            pending.removeAll()
        }
    }

    /// Created on the first request only, so a loader built and discarded during a view update
    /// never opens a session that would keep it alive.
    private func activeSession() -> URLSession {
        if let session {
            return session
        }
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.underlyingQueue = queue
        let created = URLSession(configuration: configuration, delegate: self, delegateQueue: operationQueue)
        session = created
        return created
    }

    static func rangeHeader(offset: Int64, length: Int, toEnd: Bool) -> String {
        toEnd ? "bytes=\(offset)-" : "bytes=\(offset)-\(offset + Int64(length) - 1)"
    }

    /// The total length after the slash of a partial response's range header, else the body length
    /// of a plain 200.
    static func totalLength(of response: HTTPURLResponse) -> Int64? {
        if let range = response.value(forHTTPHeaderField: "Content-Range"),
           let total = range.split(separator: "/").last.flatMap({ Int64($0) })
        {
            return total
        }
        return response.expectedContentLength > 0 ? response.expectedContentLength : nil
    }

    /// AVFoundation wants a UTI. A generic MIME type tells it nothing, so the file's own extension
    /// decides then.
    static func contentType(mimeType: String?, fileExtension: String) -> String? {
        if let mimeType, mimeType != "application/octet-stream", let type = UTType(mimeType: mimeType),
           type.conforms(to: .audiovisualContent)
        {
            return type.identifier
        }
        return UTType(filenameExtension: fileExtension)?.identifier
    }
}

extension ClientCertificateAssetLoader: AVAssetResourceLoaderDelegate {
    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        var request = URLRequest(url: remoteURL)
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        var offset: Int64 = 0
        if let dataRequest = loadingRequest.dataRequest {
            offset = dataRequest.requestedOffset
            request.setValue(
                Self.rangeHeader(
                    offset: offset,
                    length: dataRequest.requestedLength,
                    toEnd: dataRequest.requestsAllDataToEndOfResource
                ),
                forHTTPHeaderField: "Range"
            )
        }
        let task = activeSession().dataTask(with: request)
        pending[task.taskIdentifier] = Pending(loadingRequest: loadingRequest, bytesToSkip: 0, requestedOffset: offset)
        task.resume()
        return true
    }

    func resourceLoader(_: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        guard let entry = pending.first(where: { $0.value.loadingRequest === loadingRequest }) else { return }
        pending[entry.key] = nil
        session?.getAllTasks { tasks in
            tasks.first { $0.taskIdentifier == entry.key }?.cancel()
        }
    }
}

extension ClientCertificateAssetLoader: URLSessionDataDelegate {
    func urlSession(
        _: URLSession, task _: URLSessionTask, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        ClientCertificateChallengeHandler.shared.handle(challenge) ?? (.performDefaultHandling, nil)
    }

    func urlSession(
        _: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard var entry = pending[dataTask.taskIdentifier] else {
            completionHandler(.cancel)
            return
        }
        guard let http = response as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode else {
            pending[dataTask.taskIdentifier] = nil
            entry.loadingRequest.finishLoading(with: URLError(.badServerResponse))
            completionHandler(.cancel)
            return
        }
        if let info = entry.loadingRequest.contentInformationRequest {
            info.contentType = Self.contentType(mimeType: http.mimeType, fileExtension: fileExtension)
            info.contentLength = Self.totalLength(of: http) ?? 0
            info.isByteRangeAccessSupported = http.statusCode == 206
        }
        if http.statusCode == 200 {
            entry.bytesToSkip = entry.requestedOffset
            pending[dataTask.taskIdentifier] = entry
        }
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard var entry = pending[dataTask.taskIdentifier] else { return }
        var chunk = data
        if entry.bytesToSkip > 0 {
            let skipped = min(Int64(chunk.count), entry.bytesToSkip)
            chunk = chunk.dropFirst(Int(skipped))
            entry.bytesToSkip -= skipped
            pending[dataTask.taskIdentifier] = entry
        }
        if !chunk.isEmpty {
            entry.loadingRequest.dataRequest?.respond(with: chunk)
        }
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let entry = pending.removeValue(forKey: task.taskIdentifier) else { return }
        if let error {
            if (error as? URLError)?.code != .cancelled {
                entry.loadingRequest.finishLoading(with: error)
            }
        } else {
            entry.loadingRequest.finishLoading()
        }
    }
}
