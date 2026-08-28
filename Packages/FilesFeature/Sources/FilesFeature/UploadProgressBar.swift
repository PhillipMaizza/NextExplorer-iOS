import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .iconSmall
    static let cancelSize: CGFloat = .iconSmall
    static let contentSpacing: CGFloat = .space12
    static let textSpacing: CGFloat = .space4
    static let horizontalPadding: CGFloat = .space16
    static let verticalPadding: CGFloat = .space12
}

/// The persistent pill shown above the tab bar while an upload is running. Tapping it opens
/// the full `UploadsView`; the trailing button cancels the whole queue.
struct UploadProgressBar: View {
    let title: String
    let progress: Double
    let onTap: () -> Void
    let onCancelAll: () -> Void

    var body: some View {
        HStack(spacing: Constants.contentSpacing) {
            IconKit.upload
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accent)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
            VStack(alignment: .leading, spacing: Constants.textSpacing) {
                Text(title)
                    .type(.body3(.semibold), style: .primary(for: .label))
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressView(value: progress)
                    .tint(Color.accent)
            }
            Button(action: onCancelAll) {
                IconKit.close
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.cancelSize, height: Constants.cancelSize)
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(L10n.Uploads.cancelAll)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .background(Color.backgroundSecondary)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

#Preview {
    UploadProgressBar(title: "Uploading 2 of 5", progress: 0.4, onTap: {}, onCancelAll: {})
}
