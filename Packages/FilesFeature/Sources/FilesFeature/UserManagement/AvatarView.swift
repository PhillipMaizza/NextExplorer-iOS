import DesignSystem
import SwiftUI

private enum Constants {
    static let maxInitials = 2
}

/// Circular avatar. The server has no profile-picture field today (confirmed against
/// `backend/src/services/users/utils.js`'s `toClientUser`), so `imageURL` is always nil in
/// practice and this always falls back to initials. `imageURL` still exists so this
/// doesn't need to change the day one ships.
struct AvatarView: View {
    let displayName: String
    let imageURL: URL?
    let size: CGFloat

    init(displayName: String, imageURL: URL? = nil, size: CGFloat) {
        self.displayName = displayName
        self.imageURL = imageURL
        self.size = size
    }

    private var initials: String {
        let letters = displayName
            .split(separator: " ")
            .prefix(Constants.maxInitials)
            .compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        Circle()
            .fill(Color.accent)
            .overlay {
                Text(initials)
                    .type(.body1(.bold), style: .primary(for: .label))
            }
    }
}

#Preview {
    AvatarView(
        displayName: "Jane Doe",
        imageURL: nil,
        size: .iconLarge
    )
    .colorScheme(.dark)
    AvatarView(
        displayName: "Jane Doe",
        imageURL: nil,
        size: .iconLarge
    )
    .colorScheme(.light)
}

