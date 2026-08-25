import Security

public enum KeychainAccessibility: Sendable {
    case afterFirstUnlock
    case whenUnlocked

    /// `ThisDeviceOnly` variants are used for both cases: without it, an item is eligible
    /// for iCloud Keychain sync/backup, so a session cookie restored onto a different
    /// device would hand that device a live, pre-authenticated session with no re-login.
    /// Session credentials must never leave the device they were issued on.
    var cfString: CFString {
        switch self {
        case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenUnlocked: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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
