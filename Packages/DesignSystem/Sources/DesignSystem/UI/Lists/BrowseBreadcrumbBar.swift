import Foundation
import Localization
import SwiftUI

private enum Constants {
    static let segmentSpacing: CGFloat = .space4
    static let chevronSize: CGFloat = .iconXSmall
    static let fullOpacity: Double = 1.0
    static let barHeight: CGFloat = .size40
    /// Room inside the capsule on both ends, so the current folder never sits against its edge.
    static let innerHorizontalPadding: CGFloat = .space24
    static let outerHorizontalMargin: CGFloat = .space16
    static let bottomMargin: CGFloat = .space8
    static let contentGap: CGFloat = .space16
}

/// `BrowseBreadcrumbBar`'s total rendered height (the capsule plus its bottom margin), shared with
/// `BrowseContentView` so its list/grid can explicitly reserve the same amount of bottom
/// scroll content inset. A `List` inside a pushed `navigationDestination` doesn't reliably extend
/// its own scroll extent to respect an ancestor's inset, letting the last row scroll out from
/// behind the bar, so `BrowseContentView` reserves this same height directly on its own
/// scrollable content instead of trusting that propagation.
public enum BrowseBreadcrumbBarMetrics {
    public static let height: CGFloat = Constants.barHeight + Constants.bottomMargin
    /// What a list reserves under its last row for the bar: its height plus a gap above it.
    public static let contentClearance: CGFloat = height + Constants.contentGap
}

/// Mirrors the web client's own path breadcrumb ("Location"): tapping any earlier segment
/// jumps straight there via the same `openPath` delegate search results use, rather than
/// popping the navigation stack one folder at a time.
///
/// A small frosted capsule floating over the bottom of the content: it hugs a short path and
/// scrolls a long one, with the content passing blurred underneath.
///
/// `rootPath`/`rootTitle`/`rootIcon` default to true server root ("Home") for Browse, but
/// Favorites overrides them to the favorited folder itself: browsing there is scoped to
/// that subtree, so the leftmost crumb should anchor on the favorite, not imply a tap on it
/// would leave the tab (server-root "Home" isn't reachable from inside Favorites at all).
///
/// `containerCrumb` prepends one more crumb *before* the root: Favorites uses it for the
/// tab's own list screen ("Favorites", `path` ""), so there's always a crumb that leaves the
/// favorited folder entirely instead of the leftmost tap just re-opening that same folder.
public struct BrowseBreadcrumbBar: View {
    let directoryPath: String
    var rootTitle: String = L10n.Browse.locations
    var rootPath: String = ""
    var rootIcon: Image? = IconKit.drive
    var containerCrumb: (title: String, path: String, icon: Image?)?
    let onSegmentTapped: (_ path: String, _ title: String) -> Void
    /// The segments' natural width: the capsule shrinks to it when the path is short.
    @State private var contentWidth: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(
        directoryPath: String,
        rootTitle: String = L10n.Browse.locations,
        rootPath: String = "",
        rootIcon: Image? = IconKit.drive,
        containerCrumb: (title: String, path: String, icon: Image?)? = nil,
        onSegmentTapped: @escaping (_ path: String, _ title: String) -> Void
    ) {
        self.directoryPath = directoryPath
        self.rootTitle = rootTitle
        self.rootPath = rootPath
        self.rootIcon = rootIcon
        self.containerCrumb = containerCrumb
        self.onSegmentTapped = onSegmentTapped
    }

    /// `directoryPath` with `rootPath` stripped off the front: segments are only ever
    /// rendered/tapped relative to the configured root.
    private var relativeDirectoryPath: String {
        guard !rootPath.isEmpty, directoryPath.hasPrefix(rootPath) else { return directoryPath }
        return String(directoryPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var pathSegments: [String] {
        relativeDirectoryPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private func cumulativePath(through index: Int) -> String {
        ([rootPath] + pathSegments[0 ... index]).filter { !$0.isEmpty }.joined(separator: "/")
    }

    /// A level's name: the leading `personal` of the root reads as "My Files".
    private func levelTitle(for path: String) -> String {
        let segment = (path as NSString).lastPathComponent
        let isFirstSegment = rootPath.isEmpty && !path.contains("/")
        return PersonalSpace.displayName(forSegment: segment, isFirstSegment: isFirstSegment)
    }

    /// A new level slides in from the trailing edge, a popped one slides back out; only fades with
    /// Reduce Motion.
    private var levelTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    private var levelAnimation: Animation? {
        DSMotion.stateFade
    }

    /// A fixed id for the trailing edge of the bar (rather than tagging the last real
    /// segment): `ScrollViewReader` needs some anchor to scroll to, and this way there's
    /// always exactly one, even at the root with no path segments at all.
    private static let trailingAnchorID = "trailing"

    /// A compact width iPhone shows no path bar anywhere: the title and the back button say where
    /// the user is, and the bar would only crowd the bottom of a small screen.
    private var isShown: Bool {
        #if os(iOS)
            horizontalSizeClass != .compact
        #elseif os(macOS)
            true
        #endif
    }

    public var body: some View {
        if isShown {
            bar
        }
    }

    private var bar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Constants.segmentSpacing) {
                    if let containerCrumb {
                        segment(title: containerCrumb.title, path: containerCrumb.path, icon: containerCrumb.icon)
                        chevron
                    }
                    segment(title: rootTitle, path: rootPath, icon: rootIcon)
                    // Keyed by each level's path, so a level pushed or popped slides in or out
                    // on its own while the ones before it stay put.
                    ForEach(pathSegments.indices.map { cumulativePath(through: $0) }, id: \.self) { path in
                        HStack(spacing: Constants.segmentSpacing) {
                            chevron
                            segment(title: levelTitle(for: path), path: path, icon: nil)
                        }
                        .transition(levelTransition)
                    }
                    // Gives `ScrollViewReader` a stable target even at the root with no path
                    // segments at all.
                    Color.clear.frame(width: 0, height: 1).id(Self.trailingAnchorID)
                }
                .padding(.horizontal, Constants.innerHorizontalPadding)
                .frame(height: Constants.barHeight)
                .animation(levelAnimation, value: directoryPath)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    // The capsule grows and shrinks with the levels; only its first size lands at once.
                    if contentWidth == nil {
                        contentWidth = width
                    } else {
                        withAnimation(levelAnimation) { contentWidth = width }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(maxWidth: contentWidth ?? .infinity)
            .frame(height: Constants.barHeight)
            // A rotation or the sidebar showing narrows the bar: bring the current folder back.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in
                proxy.scrollTo(Self.trailingAnchorID, anchor: .trailing)
            }
            .clipShape(Capsule())
            .dsGlass(in: Capsule())
            .padding(.horizontal, Constants.outerHorizontalMargin)
            .padding(.bottom, Constants.bottomMargin)
            .frame(maxWidth: .infinity)
            // The path is always visible at the trailing edge: deep breadcrumbs otherwise
            // stay scrolled to "Home" after navigating into a new folder, hiding exactly the
            // segment that just changed.
            .onAppear { proxy.scrollTo(Self.trailingAnchorID, anchor: .trailing) }
            .onChange(of: directoryPath) { _, _ in
                withAnimation(DSMotion.stateFade) {
                    proxy.scrollTo(Self.trailingAnchorID, anchor: .trailing)
                }
            }
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

#Preview("Favorites: container crumb") {
    BrowseBreadcrumbBar(
        directoryPath: "Media/Photos/Vacation/2024",
        rootTitle: "Photos",
        rootPath: "Media/Photos",
        rootIcon: IconKit.folderFill,
        containerCrumb: ("Favorites", "", IconKit.starFill)
    ) { _, _ in }
}

/// The account's private folder when the server has personal folders on. The backend reaches it
/// through the logical `personal` path space (`parsePathSpace` in `backend/src/utils/pathUtils.js`)
/// and never lists it among the volumes, so the root screen offers it as its own entry.
public enum PersonalSpace {
    public static let rootPath = "personal"

    /// A breadcrumb or title for a path segment: the leading `personal` reads as "My Files".
    public static func displayName(forSegment segment: String, isFirstSegment: Bool) -> String {
        isFirstSegment && segment == rootPath ? L10n.Browse.myFiles : segment
    }
}
