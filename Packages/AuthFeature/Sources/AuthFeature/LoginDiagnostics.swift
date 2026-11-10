import AuthClient
import ComposableArchitecture
import Foundation

/// What the sign in screen saw at each step, kept in memory so someone whose sign in fails can
/// share it. The text is for the developer and stays in English. It never holds the password,
/// the address, the name that was typed or the code: only their shape.
///
/// Equality ignores the contents on purpose. The log records what happened, it is not behavior
/// state, and a test asserting state should not have to restate it. Tests read `entries`.
struct LoginDiagnostics: Equatable, Sendable {
    static func == (_: LoginDiagnostics, _: LoginDiagnostics) -> Bool {
        true
    }

    struct Entry: Equatable, Sendable {
        let timestamp: Date
        let text: String
        let isProblem: Bool
    }

    private enum Constants {
        static let maxEntries = 200
        static let maxDetailLength = 160
        static let redactedHost = "<server>"
        static let sixDigitCodeLength = 6
        static let problemMarker = "PROBLEM "
        static let unknown = "unknown"
    }

    private(set) var entries: [Entry] = []

    var hasProblem: Bool {
        entries.contains(where: \.isProblem)
    }

    mutating func record(_ text: String, isProblem: Bool = false, at timestamp: Date) {
        entries.append(Entry(timestamp: timestamp, text: text, isProblem: isProblem))
        if entries.count > Constants.maxEntries {
            entries.removeFirst(entries.count - Constants.maxEntries)
        }
    }

    func rendered(header: [String]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = entries.map { "\(formatter.string(from: $0.timestamp)) \($0.isProblem ? Constants.problemMarker : "")\($0.text)" }
        return (header + [""] + lines).joined(separator: "\n")
    }

    static func environmentHeader(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> [String] {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? Constants.unknown
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? Constants.unknown
        return [
            "NextExplorer \(version) (\(build))",
            "OS: \(processInfo.operatingSystemVersionString)",
        ]
    }

    static func describe(server url: URL) -> String {
        let port = url.port.map { "port \($0)" } ?? "default port"
        return "\(url.scheme ?? Constants.unknown), \(port)"
    }

    static func describe(identifier raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let shape = trimmed.contains("@") ? "email shaped" : "username shaped"
        var notes: [String] = []
        if trimmed.count != raw.count {
            notes.append("surrounding whitespace removed")
        }
        if trimmed.contains(where: { !$0.isASCII }) {
            notes.append("non ASCII characters")
        }
        let suffix = notes.isEmpty ? "" : ", " + notes.joined(separator: ", ")
        return "\(shape), \(trimmed.count) characters\(suffix)"
    }

    static func describe(password: String) -> String {
        password.isEmpty ? "empty" : "set"
    }

    static func describe(code raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSixDigits = trimmed.count == Constants.sixDigitCodeLength && trimmed.allSatisfy(\.isNumber)
        return isSixDigits ? "6 digits" : "other, \(trimmed.count) characters"
    }

    static func describe(_ error: AuthClientError, host: String?) -> String {
        switch error {
        case .invalidCredentials: "rejected: server answered 401, no account matches that name and password"
        case .sessionExpired: "server answered 401 for the session"
        case .sessionCookieMissing: "sign in succeeded but no session cookie was found"
        case let .network(detail): "network error: \(redacted(detail, host: host))"
        case let .decoding(detail): "unexpected response: \(redacted(detail, host: host))"
        case let .keychain(detail): "keychain error: \(redacted(detail, host: host))"
        case let .server(statusCode): "server answered \(statusCode)"
        case .noAuthMethodsEnabled: "server has no sign in methods enabled"
        case .oidcCancelled: "single sign on was dismissed"
        case let .oidcFailed(detail): "single sign on failed: \(redacted(detail, host: host))"
        case .secondFactorRequired: "password accepted, server asks for a second factor code"
        case .invalidCode: "code rejected by the server"
        case .secondFactorExpired: "server no longer has a sign in waiting for a code"
        case .rateLimited: "server answered 429, too many attempts or account locked"
        case .clientCertificateRequired: "TLS handshake wants a client certificate, none installed"
        case .clientCertificateRejected: "TLS handshake refused the installed client certificate"
        }
    }

    static func isProblem(_ error: AuthClientError) -> Bool {
        switch error {
        case .secondFactorRequired, .oidcCancelled: false
        default: true
        }
    }

    private static func redacted(_ detail: String, host: String?) -> String {
        var text = detail
        if let host, !host.isEmpty {
            text = text.replacingOccurrences(of: host, with: Constants.redactedHost, options: .caseInsensitive)
        }
        return String(text.prefix(Constants.maxDetailLength))
    }
}

/// Stamps each log entry. Its own key rather than `\.date`, so a test that never looks at the log
/// does not have to provide a date.
private enum LoginLogDateKey: DependencyKey {
    static let liveValue: @Sendable () -> Date = { Date() }
    static let testValue: @Sendable () -> Date = { Date(timeIntervalSince1970: 0) }
}

extension DependencyValues {
    var loginLogDate: @Sendable () -> Date {
        get { self[LoginLogDateKey.self] }
        set { self[LoginLogDateKey.self] = newValue }
    }
}
