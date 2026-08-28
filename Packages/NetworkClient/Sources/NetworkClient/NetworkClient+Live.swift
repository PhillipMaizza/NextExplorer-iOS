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
                    // A per-task delegate for progress only. It doesn't implement the
                    // auth-challenge method, so server-trust evaluation falls back to the
                    // session-level `URLSessionAuthDelegate`.
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
