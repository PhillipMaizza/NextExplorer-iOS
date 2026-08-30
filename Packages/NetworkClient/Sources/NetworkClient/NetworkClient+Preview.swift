import Foundation

private enum Constants {
    static let downloadTempFilePrefix = "preview-download-"
    static let cannedResponseBody = "{}"
    static let fallbackURLString = "https://preview.invalid"
}

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
            try Self.cannedDownload(for: request)
        },
        lowPriorityDownload: { request in
            try Self.cannedDownload(for: request)
        }
    )

    private static func cannedDownload(for request: URLRequest) throws -> (URL, HTTPURLResponse) {
        let (data, response) = try cannedResponse(for: request)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Constants.downloadTempFilePrefix)\(UUID().uuidString)")
        try data.write(to: fileURL)
        return (fileURL, response)
    }

    private static func cannedResponse(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
        guard
            let url = request.url ?? URL(string: Constants.fallbackURLString),
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            throw NetworkError.invalidResponse
        }
        return (Data(Constants.cannedResponseBody.utf8), response)
    }
}
