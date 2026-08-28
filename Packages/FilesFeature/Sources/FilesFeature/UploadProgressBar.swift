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

/// Shared flags/metrics so screens deep in the tree can reserve bottom scroll clearance for
/// the app-level upload bar without plumbing `MainTabFeature`'s state down to them.
enum UploadBarChrome {
    /// `@Shared(.inMemory)` key: `true` while `UploadProgressBar` is on screen. Written by
    /// `MainTabView`, read by list screens for their bottom inset.
    static let visibilityKey = "uploadBarVisible"
    /// Rendered height (content + padding) plus a gap — what a list adds to its bottom inset.
    static let clearance: CGFloat = 88
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
                    .tint(Color.positive)
            }
            Button(action: onCancelAll) {
                IconKit.closeCircle
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
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: .radiusControl))
        .elevation(.level4)
        .contentShape(RoundedRectangle(cornerRadius: .radiusControl))
        .onTapGesture(perform: onTap)
    }
}

/// Same pill, shown once the queue drains with failures still in it: a warning, the count,
/// and a Retry action. `onDismiss` clears the failed jobs.
struct UploadFailedBar: View {
    let count: Int
    let onRetry: () -> Void
    let onDismiss: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: Constants.contentSpacing) {
            IconKit.warning
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.negative)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
            Text(count == 1 ? L10n.Uploads.barFailedOne : L10n.Uploads.barFailedMany(count))
                .type(.body3(.semibold), style: .primary(for: .label))
                .lineLimit(1)
            Spacer(minLength: Constants.contentSpacing)
            Button(action: onRetry) {
                Text(L10n.Common.retry)
                    .type(.body3(.semibold), style: .link)
            }
            .buttonStyle(DSHapticButtonStyle())
            Button(action: onDismiss) {
                IconKit.closeCircle
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.cancelSize, height: Constants.cancelSize)
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(L10n.Common.close)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: .radiusControl))
        .elevation(.level4)
        .contentShape(RoundedRectangle(cornerRadius: .radiusControl))
        .onTapGesture(perform: onTap)
    }
}

#Preview {
    VStack {
        UploadProgressBar(title: "Uploading 2 of 5", progress: 0.4, onTap: {}, onCancelAll: {})
        UploadFailedBar(count: 3, onRetry: {}, onDismiss: {}, onTap: {})
    }
    .padding()
}
