import CoreModels
import Foundation

/// Wire types for the local session-cookie auth endpoints (`/api/auth/*`).
/// See `LocalAuthService.swift`.
extension LocalAuthService {
    /// The server's `/api/auth/login` route takes `identifier || email || username` and matches
    /// it against either the email or the username (`attemptLocalLogin` in
    /// `backend/src/services/users/localAuth.js`). `email` is the oldest field name and works on
    /// every server version, so the typed value is sent under it whether it is an email or not.
    struct LoginRequestBody: Encodable {
        let email: String
        let password: String
    }

    /// The body of `POST /api/auth/oidc/exchange`: the one time code from the mobile bridge
    /// callback plus the PKCE verifier that proves this app started the flow. Confirmed against
    /// `backend/src/routes/auth.js` and `backend/src/services/oidcMobileBridge.js`.
    struct OIDCExchangeRequestBody: Encodable {
        let code: String
        let code_verifier: String
    }

    /// `/api/auth/login` and `/api/auth/me` both wrap the user object under a `"user"`
    /// key, and `/me` can return a 200 with `user: null` for an expired/absent session
    /// rather than a 401: confirmed against `backend/src/routes/auth.js`.
    struct UserEnvelope: Decodable {
        let user: User?
    }
}
