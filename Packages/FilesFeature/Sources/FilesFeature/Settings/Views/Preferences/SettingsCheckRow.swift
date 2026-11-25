import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowSpacing: CGFloat = .space2
    static let iconSize: CGFloat = .iconSmall
    static let checkmarkSize: CGFloat = .iconSmall
}

struct SettingsCheckRow: View {
    let title: String
    var subtitle: String?
    var icon: Image?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon {
                    Label {
                        titles
                    } icon: {
                        icon
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Color.secondaryDS)
                            .frame(width: Constants.iconSize, height: Constants.iconSize)
                    }
                } else {
                    titles
                }
                Spacer()
                if isSelected {
                    IconKit.checkmark
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.accent)
                        .frame(width: Constants.checkmarkSize, height: Constants.checkmarkSize)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DSMotion.pop, value: isSelected)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: Constants.rowSpacing) {
            Text(title).type(.body2(.regular), style: .primaryOnSurface)
            if let subtitle {
                Text(subtitle).type(.body3(.regular), style: .secondary)
            }
        }
    }
}

#Preview {
    List {
        SettingsCheckRow(title: L10n.Sort.name, icon: IconKit.textformat, isSelected: true) {}
        SettingsCheckRow(title: L10n.Sort.size, icon: IconKit.size, isSelected: false) {}
        SettingsCheckRow(
            title: L10n.Language.systemDefault,
            subtitle: L10n.Language.systemDefaultSubtitle,
            isSelected: false
        ) {}
    }
}
