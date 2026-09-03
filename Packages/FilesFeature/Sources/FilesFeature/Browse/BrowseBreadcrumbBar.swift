import DesignSystem
import Foundation
import Localization
import SwiftUI

private enum Constants {
    static let segmentSpacing: CGFloat = .space4
    static let verticalPadding: CGFloat = .space16
    static let chevronSize: CGFloat = .iconXSmall
    static let fullOpacity: Double = 1.0
    /// Empty width after the last segment (also the scroll anchor) — keeps the current
    /// folder's name off the very edge when the bar is scrolled to its trailing end.
    static let trailingInset: CGFloat = .space16
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
///
/// `rootPath`/`rootTitle`/`rootIcon` default to true server root ("Home") for Browse, but
/// Favorites overrides them to the favorited folder itself — browsing there is scoped to
/// that subtree, so the leftmost crumb should anchor on the favorite, not imply a tap on it
/// would leave the tab (server-root "Home" isn't reachable from inside Favorites at all).
///
/// `containerCrumb` prepends one more crumb *before* the root — Favorites uses it for the
/// tab's own list screen ("Favorites", `path` ""), so there's always a crumb that leaves the
/// favorited folder entirely instead of the leftmost tap just re-opening that same folder.
struct BrowseBreadcrumbBar: View {
    let directoryPath: String
    var rootTitle: String = L10n.Browse.locations
    var rootPath: String = ""
    var rootIcon: Image? = IconKit.drive
    var containerCrumb: (title: String, path: String, icon: Image?)?
    let onSegmentTapped: (_ path: String, _ title: String) -> Void

    /// `directoryPath` with `rootPath` stripped off the front — segments are only ever
    /// rendered/tapped relative to the configured root.
    private var relativeDirectoryPath: String {
        guard !rootPath.isEmpty, directoryPath.hasPrefix(rootPath) else { return directoryPath }
        return String(directoryPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var pathSegments: [String] {
        relativeDirectoryPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private func cumulativePath(through index: Int) -> String {
        ([rootPath] + pathSegments[0...index]).filter { !$0.isEmpty }.joined(separator: "/")
    }

    /// A fixed id for the trailing edge of the bar (rather than tagging the last real
    /// segment) — `ScrollViewReader` needs some anchor to scroll to, and this way there's
    /// always exactly one, even at the root with no path segments at all.
    private static let trailingAnchorID = "trailing"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Constants.segmentSpacing) {
                    if let containerCrumb {
                        segment(title: containerCrumb.title, path: containerCrumb.path, icon: containerCrumb.icon)
                        chevron
                    }
                    segment(title: rootTitle, path: rootPath, icon: rootIcon)
                    ForEach(pathSegments.indices, id: \.self) { index in
                        chevron
                        segment(title: pathSegments[index], path: cumulativePath(through: index), icon: nil)
                    }
                    // Trailing spacer doubling as the scroll anchor: keeps the rightmost
                    // segment readable (not flush against the edge) when scrolled to the end,
                    // and gives `ScrollViewReader` a stable target even at the root with no
                    // path segments at all.
                    Color.clear.frame(width: Constants.trailingInset, height: 1).id(Self.trailingAnchorID)
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
            .hapticFeedback(.selection, trigger: directoryPath)
        }
    }

    private var chevron: some View {
        IconKit.chevronRight
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.secondaryDS)
            .frame(width: Constants.chevronSize, height: Constants.chevronSize)
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
                        .foregroundStyle(Color.accent)
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
        // The segment label is just a folder name; the hint tells VoiceOver what tapping does.
        // The current segment is a no op, so it gets no hint.
        .accessibilityHint(isCurrent ? "" : L10n.Browse.breadcrumbHint)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
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

#Preview("Favorites — container crumb") {
    BrowseBreadcrumbBar(
        directoryPath: "Media/Photos/Vacation/2024",
        rootTitle: "Photos",
        rootPath: "Media/Photos",
        rootIcon: IconKit.folderFill,
        containerCrumb: ("Favorites", "", IconKit.starFill)
    ) { _, _ in }
}
