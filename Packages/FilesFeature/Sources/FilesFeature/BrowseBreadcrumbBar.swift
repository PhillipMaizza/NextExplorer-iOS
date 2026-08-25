import DesignSystem
import SwiftUI

private enum Constants {
    static let segmentSpacing: CGFloat = .space4
    static let verticalPadding: CGFloat = .space8
    static let chevronSize: CGFloat = .iconXSmall
    static let fullOpacity: Double = 1.0
}

/// Mirrors the web client's own path breadcrumb ("Location"): tapping any earlier segment
/// jumps straight there via the same `openPath` delegate search results use, rather than
/// popping the navigation stack one folder at a time.
struct BrowseBreadcrumbBar: View {
    let directoryPath: String
    let onSegmentTapped: (_ path: String, _ title: String) -> Void

    private var pathSegments: [String] {
        directoryPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private func cumulativePath(through index: Int) -> String {
        pathSegments[0...index].joined(separator: "/")
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.segmentSpacing) {
                segment(title: "Home", path: "", icon: IconKit.house)
                ForEach(pathSegments.indices, id: \.self) { index in
                    IconKit.chevronRight
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.secondaryDS)
                        .frame(width: Constants.chevronSize, height: Constants.chevronSize)
                    segment(title: pathSegments[index], path: cumulativePath(through: index), icon: nil)
                }
            }
            .padding(.horizontal, .space16)
            .padding(.vertical, Constants.verticalPadding)
        }
        .background(Color.backgroundSecondary)
    }

    private func segment(title: String, path: String, icon: Image?) -> some View {
        let isCurrent = path == directoryPath
        let trait: Typography.Trait = isCurrent ? .bold : .regular
        let style: Typography.TextStyle = isCurrent ? .link : .secondary
        return Button {
            // Tapping the current segment would otherwise reset this same folder's
            // `BrowseFeature.State` (losing scroll position/search), for no visible change.
            guard !isCurrent else { return }
            onSegmentTapped(path, title)
        } label: {
            HStack(spacing: Constants.segmentSpacing) {
                if let icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: Constants.chevronSize, height: Constants.chevronSize)
                }
                Text(title)
                    .type(.body3(trait), style: style)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        // No `.disabled(isCurrent)`: disabling a `Button` dims it even with `.plain` style,
        // and the current segment should read at full opacity, not greyed out.
        .opacity(Constants.fullOpacity)
    }
}

#Preview("Root") {
    BrowseBreadcrumbBar(directoryPath: "") { _, _ in }
}

#Preview("One level deep") {
    BrowseBreadcrumbBar(directoryPath: "Photos") { _, _ in }
}

#Preview("Deeply nested") {
    BrowseBreadcrumbBar(directoryPath: "Photos/Vacation/2024/Summer/Beach") { _, _ in }
}
