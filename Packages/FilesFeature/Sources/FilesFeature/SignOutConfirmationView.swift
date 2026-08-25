import DesignSystem
import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .iconMedium
    static let closeIconSize: CGFloat = .iconXSmall
    static let closeButtonPadding: CGFloat = .space8
    static let contentSpacing: CGFloat = .space16
    static let buttonSpacing: CGFloat = .space12
    static let horizontalPadding: CGFloat = .space24
    static let topPadding: CGFloat = .space24
    static let bottomPadding: CGFloat = .space16
}

struct SignOutConfirmationView: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        DynamicHeightSheet {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            HStack {
                IconKit.signOut
                    .resizable()
                    .foregroundStyle(Color.primaryDS)
                    .frame(width: Constants.iconSize, height: Constants.iconSize)

                Spacer()

                Button(action: onCancel) {
                    IconKit.xmark
                        .resizable()
                        .foregroundStyle(Color.primaryDS)
                        .frame(width: Constants.closeIconSize, height: Constants.closeIconSize)
                        .padding(Constants.closeButtonPadding)
                        .background(Circle().fill(Color.backgroundSecondary))
                }
            }

            Text("Are you sure?").type(.headline3, style: .primary(for: .label))
            Text("You'll need to sign in again to access your files.").type(.body1(.regular), style: .secondary)

            VStack(spacing: Constants.buttonSpacing) {
                DSButton("Log Out", style: .failure, size: .large, action: onConfirm)
                DSButton("Cancel", style: .secondary, size: .large, action: onCancel)
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
        .padding(.bottom, Constants.bottomPadding)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SignOutConfirmationView(onCancel: {}, onConfirm: {})
        }
}
