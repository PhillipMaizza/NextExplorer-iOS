import Foundation
@testable import NetworkClient
import Testing
import TestUtils

@Suite("HTTP vocabulary")
struct HTTPTests {
    private struct MethodCase: Sendable {
        let method: HTTPMethod
        let wire: String
    }

    private static let methodCases = [
        MethodCase(method: .get, wire: "GET"),
        MethodCase(method: .head, wire: "HEAD"),
        MethodCase(method: .post, wire: "POST"),
        MethodCase(method: .put, wire: "PUT"),
        MethodCase(method: .patch, wire: "PATCH"),
        MethodCase(method: .delete, wire: "DELETE"),
    ]

    @Test("a request built with a method carries the exact wire verb and the given URL", arguments: methodCases)
    private func requestCarriesWireVerb(_ testCase: MethodCase) {
        let request = URLRequest(url: TestHost.serverURL, method: testCase.method)
        #expect(request.httpMethod == testCase.wire)
        #expect(request.url == TestHost.serverURL)
    }

    @Test("the JSON content type helper sets the exact header once and replaces an earlier value")
    func jsonContentTypeReplacesExistingHeader() {
        var request = URLRequest(url: TestHost.serverURL, method: .post)
        request.setValue(MIMEType.octetStream, forHTTPHeaderField: HTTPHeaderField.contentType)
        request.setJSONContentType()
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.allHTTPHeaderFields?.count == 1)
    }

    @Test("header names and media types are the exact wire strings")
    func wireStrings() {
        #expect(HTTPHeaderField.contentType == "Content-Type")
        #expect(HTTPHeaderField.accept == "Accept")
        #expect(HTTPHeaderField.ifNoneMatch == "If-None-Match")
        #expect(HTTPHeaderField.etag == "ETag")
        #expect(MIMEType.json == "application/json")
        #expect(MIMEType.octetStream == "application/octet-stream")
        #expect(MIMEType.jpeg == "image/jpeg")
    }

    @Test("the multipart content type names the boundary")
    func multipartContentType() {
        #expect(MIMEType.multipartFormData(boundary: "XYZ") == "multipart/form-data; boundary=XYZ")
        #expect(MIMEType.multipartFormData(boundary: "") == "multipart/form-data; boundary=")
    }
}
