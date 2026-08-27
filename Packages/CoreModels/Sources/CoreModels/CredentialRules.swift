import Foundation

/// Client side checks on credential input, so the UI can reject bad values before a request.
/// The backend stays the source of truth: `services/users/localAuth.js` enforces the password
/// length (`password.length < 6`) and a unique non empty email, but does not validate email
/// shape. The shape check here is a UX nicety, matching the login form.
public enum CredentialRules {
    /// The backend rejects anything shorter with `VALIDATION_PASSWORD_TOO_SHORT`.
    public static let minimumPasswordLength = 6

    /// Basic `x@y.z` shape check, the same regex the login form uses.
    public static func isEmailShaped(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    public static func isPasswordLongEnough(_ text: String) -> Bool {
        text.count >= minimumPasswordLength
    }
}
