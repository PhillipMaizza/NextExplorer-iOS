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
    /// `@Shared(.inMemory)` key: `true` while a bar is on screen. Written by `MainTabView`,
    /// read by list screens for their bottom inset.
    static let visibilityKey = "uploadBarVisible"
    /// `@Shared(.inMemory)` key: the bar's live rendered height (content + padding), written by
    /// `MainTabView` from a `GeometryReader`. `fallbackHeight` is only the first frame stand in
    /// before that measurement lands, and the ceiling if measurement ever reads zero.
    static let heightKey = "uploadBarHeight"
    static let fallbackHeight: CGFloat = 72
    /// Gap a list leaves between its last row and the floating bar.
    static let gap: CGFloat = .space16
}

/// The persistent pill shown above the tab bar while an upload or download queue runs. Tapping
/// it opens that queue's sheet; the trailing button cancels the whole queue. A `nil` progress
/// (a transfer of unknown length) shows an indeterminate bar.
struct TransferProgressBar: View {
    let icon: Image
    let title: String
    let progress: Double?
    /// Optional sizes and time left under the bar.
    var detail: String?
    let cancelLabel: String
    let onTap: () -> Void
    let onCancelAll: () -> Void

    var body: some View {
        HStack(spacing: Constants.contentSpacing) {
            icon
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accent)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
            VStack(alignment: .leading, spacing: Constants.textSpacing) {
                Text(title)
                    .type(.body3(.semibold), style: .primaryOnSurface)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let progress {
                    ProgressView(value: progress)
                        .tint(Color.positive)
                } else {
                    IndeterminateProgressBar()
                }
                if let detail {
                    Text(detail)
                        .type(.caption(.regular), style: .secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            Button(action: onCancelAll) {
                IconKit.closeCircle
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.cancelSize, height: Constants.cancelSize)
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(cancelLabel)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: .radiusCard, style: .continuous))
        .elevation(.level4)
        .contentShape(RoundedRectangle(cornerRadius: .radiusCard, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text(detail ?? progress?.formatted(.percent.precision(.fractionLength(0))) ?? ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onTap)
        .accessibilityAction(named: Text(cancelLabel), onCancelAll)
    }
}

/// Same pill, shown once the queue drains with failures still in it: a warning, the count,
/// and a Retry action. `onDismiss` clears the failed jobs.
struct TransferFailedBar: View {
    let label: String
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
            Text(label)
                .type(.body3(.semibold), style: .primaryOnSurface)
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
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: .radiusCard, style: .continuous))
        .elevation(.level4)
        .contentShape(RoundedRectangle(cornerRadius: .radiusCard, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onTap)
        .accessibilityAction(named: Text(L10n.Common.retry), onRetry)
        .accessibilityAction(named: Text(L10n.Common.close), onDismiss)
    }
}

/// A thin bar with a sliding segment, for transfers whose total size isn't known.
struct IndeterminateProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    private enum Metrics {
        static let height: CGFloat = 4
        static let segmentFraction: CGFloat = 0.35
        static let duration: Double = 1.1
        static let trackOpacity: Double = 0.2
    }

    var body: some View {
        GeometryReader { proxy in
            let segment = proxy.size.width * Metrics.segmentFraction
            Capsule()
                .fill(Color.positive.opacity(Metrics.trackOpacity))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.positive)
                        .frame(width: segment)
                        .offset(x: isAnimating ? proxy.size.width : (reduceMotion ? 0 : -segment))
                        .animation(
                            reduceMotion ? nil : .linear(duration: Metrics.duration).repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                }
                .clipShape(Capsule())
        }
        .frame(height: Metrics.height)
        .onAppear { isAnimating = !reduceMotion }
    }
}

#Preview("Determinate") {
    TransferProgressBar(
        icon: IconKit.upload, title: "Uploading 3 files", progress: 0.4,
        cancelLabel: "Cancel all", onTap: {}, onCancelAll: {}
    )
    .padding()
}

#Preview("With detail") {
    TransferProgressBar(
        icon: IconKit.download, title: "Downloading movie.mkv", progress: 0.26,
        detail: "412 MB of 1.6 GB · 2 min left",
        cancelLabel: "Cancel all", onTap: {}, onCancelAll: {}
    )
    .padding()
}

#Preview("Indeterminate") {
    TransferProgressBar(
        icon: IconKit.download, title: "Downloading Photos.zip", progress: nil,
        detail: "312 MB", cancelLabel: "Cancel all", onTap: {}, onCancelAll: {}
    )
    .padding()
}

#Preview("Failed") {
    TransferFailedBar(label: "3 downloads failed", onRetry: {}, onDismiss: {}, onTap: {})
        .padding()
}
