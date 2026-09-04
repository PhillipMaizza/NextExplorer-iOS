import CoreModels
import Foundation

/// Wire types for the local session-cookie auth endpoints (`/api/auth/*`).
/// See `LocalAuthService.swift`.
extension LocalAuthService {
    /// The server's `/api/auth/login` route destructures `{ email, password, username }` from
    /// the body and only ever looks the user up by the `email` column — confirmed against
    /// `backend/src/routes/auth.js` and `backend/src/services/users/localAuth.js`. A `username`
    /// field is accepted as a fallback source for the value but is never queried on its own,
    /// so this must be sent as `email` regardless of which the user actually typed.
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
    /// rather than a 401 — confirmed against `backend/src/routes/auth.js`.
    struct UserEnvelope: Decodable {
        let user: User?
    }
}
