import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .iconSmall
    static let titleSpacing: CGFloat = .space2
}

/// A labeled `Toggle` with a leading icon, the shape every settings-style switch row in
/// the app shares (dark mode, show hidden files, show thumbnails, ...). `subtitle` adds a
/// secondary explanatory line under the title, for options whose effect isn't obvious from
/// the title alone.
public struct DSToggleRow: View {
    private let title: String
    private let subtitle: String?
    private let icon: Image
    @Binding private var isOn: Bool

    public init(title: String, subtitle: String? = nil, icon: Image, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self._isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: .leading, spacing: Constants.titleSpacing) {
                    Text(title).type(.body2(.regular), style: .primary(for: .label))
                    if let subtitle {
                        Text(subtitle).type(.body3(.regular), style: .secondary)
                    }
                }
            } icon: {
                icon
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
            }
        }
        .tint(Color.accent)
        .hapticFeedback(.selection, trigger: isOn)
    }
}

#Preview {
    VStack(spacing: .space16) {
        DSToggleRow(title: "Dark Mode", icon: IconKit.darkMode, isOn: .constant(true))
        DSToggleRow(title: "Show Hidden Files", icon: IconKit.eye, isOn: .constant(false))
        DSToggleRow(title: "Show Thumbnails", icon: IconKit.photo, isOn: .constant(true))
        DSToggleRow(
            title: "Remove Archives After Download",
            subtitle: "Deletes the .zip created to download a folder from the server once it's saved.",
            icon: IconKit.delete,
            isOn: .constant(false)
        )
    }
    .padding(.space16)
    .background(Color.backgroundPrimary)
}
