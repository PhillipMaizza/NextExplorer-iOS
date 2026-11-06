import Foundation

/// The server a client certificate belongs to: lowercased host plus effective port, the same
/// pair a TLS challenge's protection space reports, so an imported identity is matched to
/// exactly the endpoint it was added for.
public struct ClientCertificateOrigin: Hashable, Sendable, Codable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host.lowercased()
        self.port = port
    }

    public init?(url: URL) {
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return nil }
        let defaultPort = url.scheme?.lowercased() == "http" ? 80 : 443
        self.init(host: host, port: url.port ?? defaultPort)
    }

    init(protectionSpace: URLProtectionSpace) {
        self.init(host: protectionSpace.host, port: protectionSpace.port)
    }

    var keychainKey: String {
        "clientIdentity.\(host):\(port)"
    }
}
