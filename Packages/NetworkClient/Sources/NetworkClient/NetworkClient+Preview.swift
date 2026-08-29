import Foundation

extension NetworkClient {
    public static let previewValue: NetworkClient = NetworkClient(
        send: { request in
            try Self.cannedResponse(for: request)
        },
        upload: { request, _, onProgress in
            onProgress(1)
            return try Self.cannedResponse(for: request)
        },
        download: { request in
            let (data, response) = try Self.cannedResponse(for: request)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("preview-download-\(UUID().uuidString)")
            try data.write(to: fileURL)
            return (fileURL, response)
        }
    )

    private static func cannedResponse(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
        guard
            let url = request.url ?? URL(string: "https://preview.invalid"),
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            throw NetworkError.invalidResponse
        }
        return (Data("{}".utf8), response)
    }
}
