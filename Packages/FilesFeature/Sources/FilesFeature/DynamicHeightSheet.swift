import DesignSystem
import SwiftUI

/// Wraps `content` in a disabled `ScrollView` and self-measures it to drive
/// `presentationDetents`, matching FreeNow's own `DSUIDynamicHeightDialogSheet`: measuring and
/// feeding a height into `presentationDetents` *after* a sheet is already presented doesn't
/// reliably resize it, so the outer container always accepts whatever size the sheet proposes
/// while `content` measures its own true, unconstrained size from the first frame.
///
/// Every self-sizing sheet in this app (currently just browse sort) is built on this,
/// rather than each re-implementing its own `GeometryReader`/`detentHeight` plumbing.
struct DynamicHeightSheet<Content: View>: View {
    @State private var detentHeight: CGFloat = 0
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                lockHeight(proxy.size.height)
                            }
                            .onChange(of: proxy.size.height) { _, newValue in
                                lockHeight(newValue)
                            }
                    }
                )
        }
        .scrollDisabled(true)
        .background(Color.backgroundPrimary)
        .presentationDetents(detentHeight > 0 ? [.height(detentHeight)] : [.medium])
        .presentationDragIndicator(.hidden)
    }

    /// Sets `detentHeight` exactly once, on the first non-zero measurement, then ignores
    /// every later change. Row count in these sheets never changes after presentation, so
    /// any later fluctuation is just incidental relayout (a selection toggling bold text, an
    /// icon's `.contentTransition` mid-morph) rather than a real content-size change — and
    /// feeding those into `presentationDetents` made the whole sheet visibly bounce.
    private func lockHeight(_ measured: CGFloat) {
        guard detentHeight == 0, measured > 0 else { return }
        detentHeight = measured
    }
}
