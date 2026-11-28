import Foundation

public enum CredentialRules {
    /// The backend rejects anything shorter with `VALIDATION_PASSWORD_TOO_SHORT`.
    public static let minimumPasswordLength = 6

    /// An `x@y` shape, as the web form's email field accepts; the server only needs one.
    public static func isEmailShaped(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^[^\s@]+@[^\s@]+$"#, options: .regularExpression) != nil
    }

    public static func isPasswordLongEnough(_ text: String) -> Bool {
        text.utf16.count >= minimumPasswordLength
    }

    public static func usernameKey(_ username: String) -> String {
        String(String.UnicodeScalarView(username.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map {
            ("A" ... "Z").contains($0) ? Unicode.Scalar($0.value + 32) ?? $0 : $0
        }))
    }

    public static func emailKey(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
