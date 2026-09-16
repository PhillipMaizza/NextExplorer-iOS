import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .iconSmall
    static let chevronSize: CGFloat = .iconXSmall
    static let rowSpacing: CGFloat = .space8
}

/// A tappable settings-style row: a leading icon, a title, and a trailing accessory
/// (disclosure chevron, a trailing detail string, or nothing). The whole row width is the
/// hit target — the shape every `Button`-driven Settings row shares, so taps land the same
/// way on every one of them.
///
/// For a switch use `DSToggleRow`; for a plain push segue a `NavigationLink` in a `List` is
/// already full width and needs nothing from here.
public struct DSNavigationRow: View {
    public enum Accessory {
        /// Disclosure chevron — the row pushes a screen.
        case chevron
        /// A trailing secondary string (a size, a current value) and no chevron.
        case detail(String)
        case none
    }

    public enum Role {
        case standard
        /// Accent-tinted title and icon — a soft-destructive action (clear cache, ...).
        case accent
        /// Error-red title and icon.
        case destructive
    }

    private let title: String
    private let icon: Image
    private let accessory: Accessory
    private let role: Role
    private let isLoading: Bool
    /// `nil` renders a static, non-interactive row (a read-only info line in the same shape).
    private let action: (() -> Void)?

    public init(
        title: String,
        icon: Image,
        accessory: Accessory = .chevron,
        role: Role = .standard,
        isLoading: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.icon = icon
        self.accessory = accessory
        self.role = role
        self.isLoading = isLoading
        self.action = action
    }

    private var titleStyle: Typography.TextStyle {
        switch role {
        case .standard: .primaryOnSurface
        case .accent: .link
        case .destructive: .error
        }
    }

    /// Navigation rows read as list items (regular); accent/destructive rows are actions and
    /// carry the weight of a button.
    private var titleTrait: Typography.Trait {
        role == .standard ? .regular : .semibold
    }

    private var iconColor: Color {
        switch role {
        case .standard: .secondaryDS
        case .accent: .accentText
        case .destructive: .negative
        }
    }

    public var body: some View {
        if let action {
            Button(role: role == .destructive ? .destructive : nil, action: action) {
                rowLabel
            }
            .buttonStyle(DSHapticButtonStyle())
            .disabled(isLoading)
        } else {
            rowLabel
        }
    }

    private var rowLabel: some View {
        Label {
            HStack(spacing: Constants.rowSpacing) {
                Text(title).type(.body2(titleTrait), style: titleStyle)
                Spacer(minLength: Constants.rowSpacing)
                accessoryView
            }
        } icon: {
            if isLoading {
                DSSpinner()
                    .tint(iconColor)
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
            } else {
                icon
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(iconColor)
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .chevron:
            IconKit.chevronRight
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.tertiaryDS)
                .frame(width: Constants.chevronSize, height: Constants.chevronSize)
        case let .detail(text):
            Text(text).type(.body2(.regular), style: .secondary)
        case .none:
            EmptyView()
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        DSNavigationRow(title: "User Management", icon: IconKit.people) {}
        DSNavigationRow(title: "Change Password", icon: IconKit.key) {}
        DSNavigationRow(title: "Clear Cache", icon: IconKit.delete, accessory: .detail("128 MB"), role: .accent) {}
        DSNavigationRow(title: "Sign Out", icon: IconKit.signOut, accessory: .none, role: .destructive) {}
    }
    .padding(.space16)
    .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: .radiusCard))
    .padding(.space16)
    .background(Color.backgroundPrimary)
}
