import Foundation

/// Client-side pre-flight checks for credential input, so the UI can reject "clearly wrong"
/// values before spending a request. The NextExplorer backend is still the source of truth:
/// it enforces the password length (`services/users/localAuth.js`: `password.length < 6`) and
/// a non-empty, unique email, but it does *not* validate email shape (it only trims and
/// lowercases) — the shape check here is a UX nicety, mirroring the login form.
public enum CredentialRules {
    /// The backend rejects any shorter password with `VALIDATION_PASSWORD_TOO_SHORT`.
    public static let minimumPasswordLength = 6

    /// Basic shape check (`x@y.z`) — the same regex the login form uses.
    public static func isEmailShaped(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    public static func isPasswordLongEnough(_ text: String) -> Bool {
        text.count >= minimumPasswordLength
    }
}
