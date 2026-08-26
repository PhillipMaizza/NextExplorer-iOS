import DesignSystem
import SwiftUI

private enum Constants {
    static let segmentSpacing: CGFloat = .space4
    static let verticalPadding: CGFloat = .space8
    static let chevronSize: CGFloat = .iconXSmall
    static let fullOpacity: Double = 1.0
}

/// `BrowseBreadcrumbBar`'s total rendered height, shared with `BrowseContentView` so its
/// list/grid can explicitly reserve the same amount of bottom scroll-content inset. The bar is
/// placed via `BrowseTabView`'s `.safeAreaInset` on the *ancestor* `NavigationStack`, but a
/// `List` inside a pushed `navigationDestination` (which is every screen the bar is actually
/// visible on — the root screen's `directoryPath` is always empty) doesn't reliably extend its
/// own scroll extent to respect that ancestor inset, letting the last row scroll out from
/// behind the bar. `BrowseContentView` reserves this same height directly on its own
/// scrollable content instead of trusting that propagation.
enum BrowseBreadcrumbBarMetrics {
    static let height: CGFloat = .size48
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

    /// A fixed id for the trailing edge of the bar (rather than tagging the last real
    /// segment) — `ScrollViewReader` needs some anchor to scroll to, and this way there's
    /// always exactly one, even at the root with no path segments at all.
    private static let trailingAnchorID = "trailing"

    var body: some View {
        ScrollViewReader { proxy in
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
                    // Zero width: an invisible trailing anchor, not a visible element — the
                    // current/rightmost segment should be what's readable at the scrolled
                    // position, not scrolled fully past it.
                    Color.clear.frame(width: 0, height: 1).id(Self.trailingAnchorID)
                }
                .padding(.horizontal, .space16)
                .padding(.vertical, Constants.verticalPadding)
            }
            .frame(height: BrowseBreadcrumbBarMetrics.height)
            .background(Color.backgroundSecondary)
            // The path is always visible at the trailing edge — deep breadcrumbs otherwise
            // stay scrolled to "Home" after navigating into a new folder, hiding exactly the
            // segment that just changed.
            .onAppear { proxy.scrollTo(Self.trailingAnchorID, anchor: .trailing) }
            .onChange(of: directoryPath) { _, _ in
                withAnimation {
                    proxy.scrollTo(Self.trailingAnchorID, anchor: .trailing)
                }
            }
        }
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
