import DesignSystem
import SwiftUI
import UIKit

/// Wraps `content` in a `ScrollView` and self-measures it to drive `presentationDetents`,
/// matching FreeNow's own `DSUIDynamicHeightDialogSheet`: measuring and feeding a height into
/// `presentationDetents` *after* a sheet is already presented doesn't reliably resize it, so
/// the outer container always accepts whatever size the sheet proposes while `content`
/// measures its own true, unconstrained size from the first frame.
///
/// Two modes:
/// * **Fixed** (`maxHeightFraction == nil`, the default): locks to the first non-zero
///   measurement, never scrolls, one detent. For small sheets whose row count can't change
///   after presentation (browse sort).
/// * **Capped** (`maxHeightFraction` set): tracks every content-size change so the sheet grows
///   as its content does, up to `maxHeightFraction` of the screen; past that `content`
///   scrolls under a pinned `footer` and `.large` becomes reachable. For sheets whose content
///   changes while open (the upload review list).
///
/// Either way there are no per-piece pixel estimates — the rendered content (and footer) is
/// the source of truth, so it stays correct under Dynamic Type and long labels.
struct DynamicHeightSheet<Content: View, Footer: View>: View {
    /// Ignore capped-mode measurement changes smaller than this — sub-point relayout churn
    /// (an icon mid `.contentTransition`) shouldn't re-propose a detent.
    private static var changeThreshold: CGFloat { 1 }

    private let maxHeightFraction: CGFloat?
    private let content: Content
    private let footer: Footer
    @State private var contentHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    init(
        maxHeightFraction: CGFloat? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.maxHeightFraction = maxHeightFraction
        self.content = content()
        self.footer = footer()
    }

    /// Height of the screen the app is actually on. `UIScreen.main` is deprecated on iOS 18
    /// and wrong under multitasking; the active window scene's own screen is the current one.
    @MainActor
    private static var screenHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen.bounds.height
            ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
                .first
            ?? 800
    }

    private var capHeight: CGFloat? {
        maxHeightFraction.map { Self.screenHeight * $0 }
    }

    /// How tall the scrolling content may be before it has to scroll — the cap less the
    /// always-visible footer.
    private var contentAllowance: CGFloat? {
        capHeight.map { max(0, $0 - footerHeight) }
    }

    private var isOverflowing: Bool {
        guard let contentAllowance else { return false }
        return contentHeight > contentAllowance
    }

    private var resolvedHeight: CGFloat {
        let visibleContent = contentAllowance.map { min(contentHeight, $0) } ?? contentHeight
        return visibleContent + footerHeight
    }

    private var detents: Set<PresentationDetent> {
        guard resolvedHeight > 0 else { return [.medium] }
        return maxHeightFraction == nil ? [.height(resolvedHeight)] : [.height(resolvedHeight), .large]
    }

    var body: some View {
        ScrollView {
            content.background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { updateContentHeight(proxy.size.height) }
                        .onChange(of: proxy.size.height) { _, newValue in updateContentHeight(newValue) }
                }
            )
        }
        .scrollDisabled(!isOverflowing)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer.background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { footerHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, newValue in footerHeight = newValue }
                }
            )
        }
        .background(Color.backgroundPrimary)
        .presentationDetents(detents)
        .presentationDragIndicator(maxHeightFraction == nil ? .hidden : .visible)
    }

    /// Fixed mode locks `contentHeight` on the first non-zero reading and ignores every later
    /// change — row count never changes there, so later fluctuation is incidental relayout
    /// that made the sheet visibly bounce. Capped mode tracks meaningful changes so the sheet
    /// follows its content.
    private func updateContentHeight(_ measured: CGFloat) {
        guard measured > 0 else { return }
        if maxHeightFraction == nil {
            guard contentHeight == 0 else { return }
        } else {
            guard abs(measured - contentHeight) >= Self.changeThreshold else { return }
        }
        contentHeight = measured
    }
}

extension DynamicHeightSheet where Footer == EmptyView {
    init(maxHeightFraction: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.init(maxHeightFraction: maxHeightFraction, content: content, footer: { EmptyView() })
    }
}
