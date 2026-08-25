import Security

public enum KeychainAccessibility: Sendable {
    case afterFirstUnlock
    case whenUnlocked

    var cfString: CFString {
        switch self {
        case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock
        case .whenUnlocked: kSecAttrAccessibleWhenUnlocked
        }
    }
}

public struct KeychainConfiguration: Sendable {
    public var service: String
    /// Unset for v1 (single app, no extensions). Passing a shared app-group identifier here
    /// later — for a Files-app Document Provider or Share Extension — is a one-line change,
    /// not a redesign: every query already routes through this configuration.
    public var accessGroup: String?
    public var accessible: KeychainAccessibility

    public init(
        service: String,
        accessGroup: String? = nil,
        accessible: KeychainAccessibility = .afterFirstUnlock
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.accessible = accessible
    }

    public static let `default` = KeychainConfiguration(service: "app.nextplorer.session")
}
