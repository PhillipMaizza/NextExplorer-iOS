import Dependencies
import Foundation

extension NetworkClient {
    public static func live(
        trustEvaluator: ServerTrustEvaluating = DefaultServerTrustEvaluator(),
        cookieStorage: HTTPCookieStorage = .shared,
        protocolClasses: [AnyClass] = []
    ) -> NetworkClient {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = cookieStorage
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        if !protocolClasses.isEmpty {
            configuration.protocolClasses = protocolClasses
        }

        let delegate = URLSessionAuthDelegate(trustEvaluator: trustEvaluator)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        return NetworkClient(
            send: { request in
                let data: Data
                let response: URLResponse
                do {
                    (data, response) = try await session.data(for: request)
                } catch {
                    throw NetworkError.transport(error.localizedDescription)
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                return (data, httpResponse)
            },
            upload: { request, bodyFileURL, onProgress in
                let data: Data
                let response: URLResponse
                do {
                    // A dedicated delegate for progress only. It carries no challenge method,
                    // so connection level challenges (server trust) are handled by
                    // `URLSessionAuthDelegate`'s session level callback.
                    (data, response) = try await session.upload(
                        for: request,
                        fromFile: bodyFileURL,
                        delegate: UploadProgressDelegate(onProgress: onProgress)
                    )
                } catch {
                    throw NetworkError.transport(error.localizedDescription)
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                return (data, httpResponse)
            },
            download: { request in
                let temporaryURL: URL
                let response: URLResponse
                do {
                    (temporaryURL, response) = try await session.download(for: request)
                } catch {
                    throw NetworkError.transport(error.localizedDescription)
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    throw NetworkError.invalidResponse
                }
                // `session.download` deletes its temp file the moment this closure returns, so
                // move it somewhere the caller controls before handing the URL back.
                let stableURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("download-\(UUID().uuidString)")
                do {
                    try FileManager.default.moveItem(at: temporaryURL, to: stableURL)
                } catch {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    throw NetworkError.transport(error.localizedDescription)
                }
                return (stableURL, httpResponse)
            }
        )
    }
}

extension NetworkClient: DependencyKey {
    public static var liveValue: NetworkClient {
        @Dependency(\.cookieStorage) var cookieStorage
        return .live(cookieStorage: cookieStorage)
    }
}

extension DependencyValues {
    public var networkClient: NetworkClient {
        get { self[NetworkClient.self] }
        set { self[NetworkClient.self] = newValue }
    }
}
