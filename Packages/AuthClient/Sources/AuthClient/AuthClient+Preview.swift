import CoreModels
import Foundation

public extension AuthClient {
    static let previewValue = AuthClient(
        fetchStatus: { _ in AuthStatus(localEnabled: true, oidcEnabled: true) },
        login: { _, _, _ in User.preview },
        loginOIDC: { _ in User.preview },
        me: { _ in User.preview },
        logout: { _ in },
        restoreSession: { nil },
        listSessions: { [] },
        activeAccountID: { nil },
        switchAccount: { _ in nil },
        removeAccount: { _ in nil },
        clearActiveSession: { nil },
        clearAllSessions: {}
    )
}

extension User {
    static let preview = User(id: "preview-user", username: "phillip", email: "phillip@example.com", roles: ["admin"])
}
