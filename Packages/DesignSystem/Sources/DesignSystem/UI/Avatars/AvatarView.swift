import SwiftUI

private enum Constants {
    static let maxInitials = 2
    /// Tinted avatars below this diameter lay out their caption at this size, then scale down
    /// as a whole, so every name in a row shrinks by the same amount.
    static let compactDiameter: CGFloat = 32
    /// Lets two letters shrink to fit the smallest avatars (the 20 pt sharer avatar on a Shared row).
    static let minimumTextScale: CGFloat = 0.4
    static let textInsetFraction: CGFloat = 0.2
}

/// Circular avatar. The server has no profile picture field today (confirmed against
/// `backend/src/services/users/utils.js`'s `toClientUser`), so `imageURL` is always nil in
/// practice and this always falls back to initials. `imageURL` still exists so this
/// doesn't need to change the day one ships.
public struct AvatarView: View {
    let displayName: String
    let imageURL: URL?
    let size: CGFloat
    /// A per person fill with white initials, sized to the circle; nil keeps the accent look.
    let tint: Color?

    public init(displayName: String, imageURL: URL? = nil, size: CGFloat, tint: Color? = nil) {
        self.displayName = displayName
        self.imageURL = imageURL
        self.size = size
        self.tint = tint
    }

    public static func person(_ name: String, size: CGFloat) -> AvatarView {
        AvatarView(displayName: name, size: size, tint: Color.categorical(for: name))
    }

    private var initials: String {
        let letters = displayName
            .split(separator: " ")
            .prefix(Constants.maxInitials)
            .compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    public var body: some View {
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
            .fill(tint ?? Color.accent)
            .overlay {
                if tint != nil {
                    AvatarLabel(text: initials, size: size, color: Color.white)
                } else {
                    Text(initials)
                        .type(.body1(.bold), style: .primaryOnSurface)
                }
            }
    }
}

/// Text centered in an avatar sized circle. Small circles render it at the compact diameter and
/// scale the result, so the same font reads at the same size across avatars and counters.
public struct AvatarLabel: View {
    let text: String
    let size: CGFloat
    let color: Color

    public init(text: String, size: CGFloat, color: Color) {
        self.text = text
        self.size = size
        self.color = color
    }

    private var layoutSize: CGFloat {
        max(size, Constants.compactDiameter)
    }

    private var textType: Typography.TextType {
        guard size < Constants.compactDiameter else { return .body3(.bold) }
        #if os(macOS)
            return .body3(.bold)
        #else
            return .caption(.bold)
        #endif
    }

    public var body: some View {
        Text(text)
            .type(textType)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(Constants.minimumTextScale)
            .padding(.horizontal, layoutSize * Constants.textInsetFraction)
            .frame(width: layoutSize, height: layoutSize)
            .scaleEffect(size / layoutSize)
            .frame(width: size, height: size)
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
    AvatarView.person("Lea Sato", size: .iconMedium)
}
