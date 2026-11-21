import Security

public enum KeychainAccessibility: Sendable {
    case afterFirstUnlock
    case whenUnlocked

    var cfString: CFString {
        switch self {
        case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenUnlocked: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }
}

public struct KeychainConfiguration: Sendable {
    public var service: String
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
