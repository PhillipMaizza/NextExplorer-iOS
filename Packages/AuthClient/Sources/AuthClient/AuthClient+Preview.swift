import CoreModels
import Foundation

public extension AuthClient {
    static let previewValue = AuthClient(
        fetchStatus: { _ in AuthStatus(localEnabled: true, oidcEnabled: true) },
        login: { _, _, _ in User.previewAdmin },
        loginTOTP: { _, _ in User.previewAdmin },
        loginOIDC: { _ in User.previewAdmin },
        me: { _ in User.previewAdmin },
        logout: { _ in },
        restoreSession: { nil },
        loadSession: { nil },
        listSessions: { [] },
        listSessionsOrThrow: { [] },
        activeAccountID: { nil },
        switchAccount: { _ in nil },
        removeAccount: { _ in nil },
        clearActiveSession: { nil },
        clearAllSessions: {}
    )
}
