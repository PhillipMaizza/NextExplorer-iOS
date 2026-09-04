import Foundation

/// Auth routes this client talks to, relative to the server base URL. Confirmed against
/// `backend/src/routes/auth.js`.
enum AuthPath {
    static let status = "api/auth/status"
    static let login = "api/auth/login"
    static let me = "api/auth/me"
    static let logout = "api/auth/logout"
    static let oidcMobileLogin = "api/auth/oidc/mobile/login"
    static let oidcExchange = "api/auth/oidc/exchange"
}
