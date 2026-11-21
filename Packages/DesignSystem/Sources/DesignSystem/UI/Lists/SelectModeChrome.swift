import SwiftUI

public extension EnvironmentValues {
    /// Whether the selection circles are out, set by `selectModeChrome`; `nil` outside it, where each
    /// row follows its own `isSelecting`.
    @Entry var areSelectionIndicatorsShown: Bool?
    /// Leaves select mode in order, set by `selectModeChrome`; `nil` outside it.
    @Entry var leaveSelectMode: DSSelectModeExit?
}

/// Leaves select mode in order: the circles slide out first, then `finish` ends select mode. Ending
/// it at once rebuilt the rows before the circles could leave. A class kept for the screen's life,
/// so the environment value never changes identity and its readers are not refreshed on every update.
@MainActor
public final class DSSelectModeExit {
    fileprivate var hideIndicators: () -> Void = {}
    private(set) var pending: Task<Void, Never>?
    /// Waits out the circles' step; a test passes one it controls.
    private let waitForIndicators: @MainActor () async -> Void

    public convenience init() {
        self.init(waitForIndicators: { try? await DSMotion.waitForStep(DSMotion.selectModeStepDuration) })
    }

    init(waitForIndicators: @escaping @MainActor () async -> Void) {
        self.waitForIndicators = waitForIndicators
    }

    /// A second call while one is under way is ignored, so a double tap never ends select mode twice.
    public func callAsFunction(_ finish: @escaping @MainActor () -> Void) {
        guard pending == nil else { return }
        hideIndicators()
        pending = Task {
            await waitForIndicators()
            guard !Task.isCancelled else { return }
            pending = nil
            finish()
        }
    }

    /// Drops an exit still waiting, once select mode ended some other way or the screen went away,
    /// so its `finish` never flips select mode back on.
    func cancel() {
        pending?.cancel()
        pending = nil
    }
}

public extension View {
    /// Enters and leaves select mode in two steps instead of all at once: entering hides the tab bar
    /// and only then slides the selection circles in; leaving slides them out and only then brings
    /// the tab bar back.
    func selectModeChrome(isSelecting: Bool) -> some View {
        modifier(SelectModeChrome(isSelecting: isSelecting))
    }
}

private struct SelectModeChrome: ViewModifier {
    let isSelecting: Bool
    @State private var isTabBarHidden = false
    @State private var areIndicatorsShown = false
    @State private var exit = DSSelectModeExit()

    func body(content: Content) -> some View {
        content
            .hidesTabBar(isTabBarHidden)
            .environment(\.areSelectionIndicatorsShown, areIndicatorsShown)
            .environment(\.leaveSelectMode, exit)
            .onAppear {
                exit.hideIndicators = {
                    withAnimation(DSMotion.selectModeStep) { areIndicatorsShown = false }
                }
                // A screen that comes back already selecting skips the steps.
                isTabBarHidden = isSelecting
                areIndicatorsShown = isSelecting
            }
            .onDisappear { exit.cancel() }
            // The tab bar slides on its own UIKit animation, which an animation completion does not
            // wait for, so each step waits out the one before it. Toggling again cancels the wait.
            .task(id: isSelecting) {
                if isSelecting {
                    withAnimation(DSMotion.selectModeStep) { isTabBarHidden = true }
                    try? await DSMotion.waitForStep(DSMotion.selectModeStepDuration)
                    guard !Task.isCancelled else { return }
                    withAnimation(DSMotion.selectModeStep) { areIndicatorsShown = true }
                } else {
                    exit.cancel()
                    // Left some other way than `leaveSelectMode` (a bulk action finishing, say).
                    if areIndicatorsShown {
                        withAnimation(DSMotion.selectModeStep) { areIndicatorsShown = false }
                        try? await DSMotion.waitForStep(DSMotion.selectModeStepDuration)
                        guard !Task.isCancelled else { return }
                    }
                    withAnimation(DSMotion.selectModeStep) { isTabBarHidden = false }
                }
            }
    }
}

#Preview {
    @Previewable @State var isSelecting = false
    TabView {
        NavigationStack {
            List(0 ..< 4, id: \.self) { index in
                Text(verbatim: "\(index)")
                    .dsListSelection(isSelecting: isSelecting, isSelected: index == 0)
            }
            .selectModeChrome(isSelecting: isSelecting)
            .toolbar {
                Button { isSelecting.toggle() } label: { IconKit.select }
            }
        }
        .tabItem { IconKit.folder }
    }
}
