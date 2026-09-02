import Localization

/// Client side mirror of the backend `ensureValidName` (`backend/src/utils/pathUtils.js`), so an
/// obviously bad folder/file name is caught inline before a network round trip. The server stays
/// the final authority: a name that passes here can still be rejected (a duplicate, a permission).
/// Validates the trimmed name, which is what the reducer actually sends.
enum FileNameValidation {
    /// A readable reason the trimmed name is invalid, or `nil` when it is acceptable. An empty
    /// name returns `nil` on purpose: that state is expressed by disabling the confirm button, not
    /// by an error the user hasn't had a chance to earn yet.
    static func errorMessage(forTrimmed name: String) -> String? {
        guard !name.isEmpty else { return nil }
        if name == "." || name == ".." { return L10n.Browse.nameErrorReserved }
        if name.contains("/") || name.contains("\\") { return L10n.Browse.nameErrorSeparators }
        return nil
    }

    static func isAcceptable(trimmed name: String) -> Bool {
        !name.isEmpty && errorMessage(forTrimmed: name) == nil
    }
}
