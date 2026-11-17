import SwiftUI

private enum Constants {
    static let horizontalPadding: CGFloat = .space16
    static let verticalPadding: CGFloat = .space12
    static let spacing: CGFloat = .space8
    static let actionHorizontalPadding: CGFloat = .space12
    static let actionVerticalPadding: CGFloat = .space4
    static let iconSize: CGFloat = .iconSmall
    static let bottomInset: CGFloat = .space16
    static let autoDismissDelay: Duration = .seconds(4.5)
    // How much of the toast's color sits over the frosted glass: enough to keep its meaning and
    // the white text legible, little enough to let the glass through. Solid on the Mac, whose
    // windows are already frosted.
    #if os(macOS)
        static let tintOpacity: Double = 1
    #else
        static let tintOpacity: Double = 0.78
    #endif
    static let progressIDPrefix = "progress:"
}

/// A brief message overlaid at the bottom of the screen: either a self-dismissing warning
/// (e.g. "Unsupported file type") or a persistent progress indicator (e.g. "Extracting…")
/// that stays until whoever's driving it clears the binding themselves.
public struct DSToastMessage: Equatable, Identifiable {
    public let id: String
    public let icon: Image?
    public let text: String
    public let backgroundColor: Color
    public let isPersistent: Bool
    /// Distinguishes a success confirmation from a warning: both are brief and
    /// auto dismissing, but only one should play a success haptic instead of an error one.
    fileprivate let isSuccess: Bool
    /// An optional trailing action button (e.g. "Open"). Not part of `Equatable`: the
    /// custom `==` below only compares `id`, so a closure here doesn't need to conform.
    public let actionTitle: String?
    public let action: (() -> Void)?

    /// A brief, auto-dismissing warning-style toast.
    public init(icon: Image, text: String) {
        // A fresh id per instance, not derived from `text`: `.task(id:)` below only restarts
        // the auto-dismiss timer when `id` changes, so two identical-text toasts triggered
        // back-to-back (e.g. tapping two different unsupported files in a row) need distinct
        // ids or the second tap's toast silently inherits whatever time was left on the
        // first one's timer instead of a fresh window.
        id = UUID().uuidString
        self.icon = icon
        self.text = text
        backgroundColor = .negative
        isPersistent = false
        isSuccess = false
        actionTitle = nil
        action = nil
    }

    /// A persistent progress toast: no auto-dismiss timer at all, since there's no fixed
    /// duration for e.g. an archive extract/compress to know in advance. Stays until the
    /// caller's own state (driving the binding) clears it.
    public static func progress(_ text: String) -> DSToastMessage {
        DSToastMessage(progressText: text)
    }

    /// A brief, auto-dismissing success confirmation (e.g. "Saved to Documents"). `actionTitle`/
    /// `action` add a trailing button (e.g. "Open"): omit both for a plain confirmation.
    public static func success(
        _ text: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> DSToastMessage {
        DSToastMessage(successText: text, actionTitle: actionTitle, action: action)
    }

    /// A brief, auto-dismissing failure toast (warning icon, `.negative` background) with an
    /// optional trailing action: e.g. "Retry" on a copy/move that didn't go through.
    public static func failure(
        _ text: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> DSToastMessage {
        DSToastMessage(failureText: text, actionTitle: actionTitle, action: action)
    }

    /// Keyed by its text, not a fresh id: callers rebuild it from state on every render, and a new
    /// id each time would restart the presenter swap forever. With no timer, reuse is harmless.
    private init(progressText: String) {
        id = Constants.progressIDPrefix + progressText
        icon = nil
        text = progressText
        backgroundColor = .secondaryDS
        isPersistent = true
        isSuccess = false
        actionTitle = nil
        action = nil
    }

    private init(successText: String, actionTitle: String?, action: (() -> Void)?) {
        id = UUID().uuidString
        icon = IconKit.checkmark
        text = successText
        backgroundColor = .positive
        isPersistent = false
        isSuccess = true
        self.actionTitle = actionTitle
        self.action = action
    }

    private init(failureText: String, actionTitle: String?, action: (() -> Void)?) {
        id = UUID().uuidString
        icon = IconKit.warning
        text = failureText
        backgroundColor = .negative
        isPersistent = false
        isSuccess = false
        self.actionTitle = actionTitle
        self.action = action
    }

    public static func == (lhs: DSToastMessage, rhs: DSToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// One toast on screen at a time, app wide. Every `dsToast` registers its message here; the
/// newest shows, and a new one waits for the current one to animate out first. A message still
/// set underneath (e.g. a persistent progress toast) comes back once the newer one clears.
@MainActor
@Observable
final class DSToastPresenter {
    static let shared = DSToastPresenter()

    private(set) var visibleID: String?
    private var requests: [(owner: UUID, id: String)] = []
    private(set) var swapTask: Task<Void, Never>?

    func set(_ message: DSToastMessage?, owner: UUID) {
        requests.removeAll { $0.owner == owner }
        if let message {
            requests.append((owner, message.id))
        }
        let target = requests.last?.id
        guard target != visibleID else { return }
        swapTask?.cancel()
        guard visibleID != nil else {
            visibleID = target
            return
        }
        visibleID = nil
        guard target != nil else { return }
        swapTask = Task { [weak self] in
            try? await DSMotion.waitForStep(.seconds(DSMotion.toastDuration))
            guard !Task.isCancelled, let self else { return }
            visibleID = requests.last?.id
        }
    }
}

private struct DSToastModifier: ViewModifier {
    @Binding var message: DSToastMessage?
    /// Extra clearance above the base inset: for screens that reserve their own chrome
    /// (e.g. a breadcrumb bar) at the bottom via `safeAreaInset`, which this overlay would
    /// otherwise sit on top of rather than above.
    var extraBottomInset: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            DSToastOverlay(message: $message, extraBottomInset: extraBottomInset)
        }
    }
}

/// A `View`, not modifier code, so the body reliably tracks `DSToastPresenter`.
private struct DSToastOverlay: View {
    @Binding var message: DSToastMessage?
    let extraBottomInset: CGFloat

    @State private var owner = UUID()
    private let presenter = DSToastPresenter.shared

    /// The message, only while it is the one on screen.
    private var visibleMessage: DSToastMessage? {
        guard let message, message.id == presenter.visibleID else { return nil }
        return message
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Keeps the overlay alive (and its lifecycle hooks firing) while nothing shows.
            Color.clear
                .allowsHitTesting(false)
            if let message = visibleMessage {
                toast(message)
            }
        }
        .animation(DSMotion.toast, value: visibleMessage)
        .onAppear { presenter.set(message, owner: owner) }
        .onChange(of: message) { _, newValue in presenter.set(newValue, owner: owner) }
        .onDisappear { presenter.set(nil, owner: owner) }
        // Persistent progress toasts (e.g. "Extracting\u{2026}") aren't outcomes: only the
        // auto dismissing failure and success styles buzz, each with its own notification kind.
        .hapticFeedback(.error, trigger: visibleMessage?.id) { _, newValue in
            newValue != nil && visibleMessage?.isPersistent == false && visibleMessage?.isSuccess == false
        }
        .hapticFeedback(.success, trigger: visibleMessage?.id) { _, newValue in
            newValue != nil && visibleMessage?.isSuccess == true
        }
    }

    private func toast(_ message: DSToastMessage) -> some View {
        HStack(spacing: Constants.spacing) {
            if let icon = message.icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
            } else {
                DSSpinner()
                    .tint(Color.primaryInverted)
            }
            Text(message.text).type(.body2(.semibold))
            if let actionTitle = message.actionTitle, let action = message.action {
                // The toast has done its job once its button is used: it goes, then the action runs.
                Button(actionTitle) {
                    self.message = nil
                    action()
                }
                .buttonStyle(DSPressableButtonStyle())
                .type(.body3(.bold))
                .foregroundStyle(Color.primaryInverted)
                .textCase(.uppercase)
                .padding(.horizontal, Constants.actionHorizontalPadding)
                .padding(.vertical, Constants.actionVerticalPadding)
                .background(DSFrostedTint(Capsule(), tint: message.backgroundColor, tintOpacity: 1))
            }
        }
        .foregroundStyle(Color.primaryInverted)
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .background { DSFrostedTint(Capsule(), tint: message.backgroundColor, tintOpacity: Constants.tintOpacity) }
        .padding(.bottom, Constants.bottomInset + extraBottomInset)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        // One VoiceOver element, spoken as a status announcement the moment it appears, since a
        // transient toast never receives focus on its own. With a button, the text and the button
        // stay apart so the button can still be reached and pressed.
        .accessibilityElement(children: message.action == nil ? .combine : .contain)
        .accessibilityAddTraits(message.action == nil ? .isStaticText : [])
        // Starts only once the toast is on screen, so time spent waiting for an earlier one
        // to leave never shortens this one.
        .task(id: message.id) {
            AccessibilityNotification.Announcement(message.text).post()
            // Under UI tests a toast with a button stays until it is used or replaced: the timer runs
            // on the wall clock, which a test that is slow to reach the button would otherwise race.
            guard !message.isPersistent, !(UITestEnvironment.isActive && message.action != nil) else { return }
            try? await Task.sleep(for: Constants.autoDismissDelay)
            // A toast swapped out early is cancelled here; clearing then would wipe its successor.
            guard !Task.isCancelled else { return }
            self.message = nil
        }
    }
}

public extension View {
    /// Shows `message` as a bottom toast while non-`nil`, auto-clearing the binding after a
    /// few seconds. Set `message` to `nil` yourself to dismiss early. `extraBottomInset` lifts
    /// the toast above any of the screen's own bottom chrome (e.g. a breadcrumb bar) that a
    /// plain overlay wouldn't otherwise know to clear.
    func dsToast(_ message: Binding<DSToastMessage?>, extraBottomInset: CGFloat = 0) -> some View {
        modifier(DSToastModifier(message: message, extraBottomInset: extraBottomInset))
    }
}

#Preview("Warning") {
    @Previewable @State var message: DSToastMessage? = DSToastMessage(
        icon: IconKit.warning,
        text: "Unsupported file type"
    )

    Color.backgroundPrimary
        .ignoresSafeArea()
        .dsToast($message)
}

#Preview("Progress") {
    @Previewable @State var message: DSToastMessage? = .progress("Extracting…")

    Color.backgroundPrimary
        .ignoresSafeArea()
        .dsToast($message)
}

#Preview("Success") {
    @Previewable @State var message: DSToastMessage? = .success("Saved to Documents")

    Color.backgroundPrimary
        .ignoresSafeArea()
        .dsToast($message)
}

#Preview("Success with action") {
    @Previewable @State var message: DSToastMessage? = .success("Moved 1 item", actionTitle: "Undo") {}

    Color.backgroundPrimary
        .ignoresSafeArea()
        .dsToast($message)
}
