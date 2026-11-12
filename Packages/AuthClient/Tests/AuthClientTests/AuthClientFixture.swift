import Foundation
import TestUtils

enum AuthClientFixture: String, FixtureFile {
    static let bundle = Bundle.module

    // MARK: common
    case commonEmptyObject = "common/empty-object"

    // MARK: second-factor
    case secondFactorErrorInvalidCode = "second-factor/error-invalid-code"
    case secondFactorErrorNotWaiting = "second-factor/error-not-waiting"
    case secondFactorLoginAdminRecoveryUnused = "second-factor/login-admin-recovery-unused"
    case secondFactorLoginRecoveryUsed = "second-factor/login-recovery-used"
    case secondFactorTotpDoneWithUser = "second-factor/totp-done-with-user"
    case secondFactorTotpRequired = "second-factor/totp-required"

    // MARK: session
    case sessionUserAdmin = "session/user-admin"
    case sessionUserNull = "session/user-null"
    case sessionUserPhillipNoRoles = "session/user-phillip-no-roles"

    // MARK: status
    case statusLocalOnly = "status/local-only"
}
