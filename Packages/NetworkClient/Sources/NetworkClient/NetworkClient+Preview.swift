import Foundation

extension NetworkClient {
    public static let previewValue: NetworkClient = NetworkClient { request in
        guard
            let url = request.url ?? URL(string: "https://preview.invalid"),
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            throw NetworkError.invalidResponse
        }
        return (Data("{}".utf8), response)
    }
}
