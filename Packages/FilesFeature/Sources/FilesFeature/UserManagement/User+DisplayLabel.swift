import CoreModels
import Foundation

extension User {
    /// The name to show for a user: the display name unless the server sent a blank one, else the
    /// username, so a message or title never renders an empty name.
    var displayLabel: String {
        guard let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return username
        }
        return displayName
    }
}
