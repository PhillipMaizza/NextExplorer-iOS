import CoreModels
import SwiftUI

private enum Constants {
    static let horizontalPadding: CGFloat = .space16
    static let verticalPadding: CGFloat = .space12
    static let spacing: CGFloat = .space8
    static let actionHorizontalPadding: CGFloat = .space12
    static let actionVerticalPadding: CGFloat = .space4
    static let actionFillOpacity: Double = .opacityFaint
    static let borderOpacity: Double = 0.25
    static let darkBorderOpacity: Double = .opacityFaint
    static let iconSize: CGFloat = .iconSmall
    static let bottomInset: CGFloat = .space16
    // How much of the surface color sits over the frosted glass: enough to keep the text legible,
    // little enough to let the glass through. Solid on the Mac, whose windows are already frosted.
    #if os(macOS)
        static let tintOpacity: Double = 1
    #else
        static let tintOpacity: Double = 0.78
    #endif
}

/// One toast on screen at a time, app wide. Every `dsToast` registers its message here; the
/// newest shows, and a new one waits for the current one to animate out first. A message still
/// set underneath (e.g. a persistent progress toast) comes back once the newer one clears.
@MainActor
@Observable
final class DSToastPresenter {
    static let shared = DSToastPresenter()

    private(set) var visibleID: String?
    @ObservationIgnored private var requests: [(owner: UUID, id: String)] = []
    @ObservationIgnored private(set) var swapTask: Task<Void, Never>?

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
        #if os(macOS)
            content.overlay(alignment: .bottomTrailing) {
                MacToastHost(message: $message, extraBottomInset: extraBottomInset)
            }
        #else
            content.overlay(alignment: .bottom) {
                DSToastOverlay(message: $message, extraBottomInset: extraBottomInset)
            }
        #endif
    }
}

/// A `View`, not modifier code, so the body reliably tracks `DSToastPresenter`.
private struct DSToastOverlay: View {
    @Binding var message: DSToastMessage?
    let extraBottomInset: CGFloat

    @State private var owner = UUID()
    @Environment(\.colorScheme) private var colorScheme
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
        capsule(message)
            .padding(.bottom, Constants.bottomInset + extraBottomInset)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: message.action == nil ? .combine : .contain)
            .accessibilityAddTraits(message.action == nil ? .isStaticText : [])
            .task(id: message.id) {
                AccessibilityNotification.Announcement(message.text).post()
                guard !message.isPersistent, !(UITestEnvironment.isActive && message.action != nil) else { return }
                try? await Task.sleep(for: DSToastMessage.autoDismissDelay)
                guard !Task.isCancelled else { return }
                self.message = nil
            }
    }

    private func run(_ message: DSToastMessage) {
        self.message = nil
        message.action?()
    }

    private func capsule(_ message: DSToastMessage) -> some View {
        HStack(spacing: Constants.spacing) {
            if let icon = message.icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                    .foregroundStyle(message.tint)
            } else {
                DSSpinner()
            }
            Text(message.text)
                .type(.body2(.semibold))
                .accessibilityIdentifier(AccessibilityIdentifiers.Toast.message)
            if let actionTitle = message.actionTitle, message.action != nil {
                // The toast has done its job once its button is used: it goes, then the action runs.
                Button(actionTitle) { run(message) }
                    .buttonStyle(DSPressableButtonStyle())
                    .type(.body3(.bold))
                    .foregroundStyle(Color.accentText)
                    .textCase(.uppercase)
                    .padding(.horizontal, Constants.actionHorizontalPadding)
                    .padding(.vertical, Constants.actionVerticalPadding)
                    .background(Capsule().fill(Color.accent.opacity(Constants.actionFillOpacity)))
            }
        }
        .foregroundStyle(Color.primaryDS)
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .background {
            DSFrostedTint(Capsule(), tint: .backgroundSecondary, tintOpacity: Constants.tintOpacity)
                .overlay {
                    Capsule().stroke(
                        Color.borderPrimary.opacity(
                            colorScheme == .dark ? Constants.darkBorderOpacity : Constants.borderOpacity
                        ),
                        lineWidth: .borderWidthHairline
                    )
                }
                .compositingGroup()
                .elevation(.level4)
        }
    }
}

public extension View {
    /// Shows `message` as a bottom toast while not `nil`, auto clearing the binding after a
    /// few seconds. Set `message` to `nil` yourself to dismiss early. `extraBottomInset` lifts
    /// the toast above any of the screen's own bottom chrome (e.g. a breadcrumb bar) that a
    /// plain overlay wouldn't otherwise know to clear.
    func dsToast(_ message: Binding<DSToastMessage?>, extraBottomInset: CGFloat = 0) -> some View {
        modifier(DSToastModifier(message: message, extraBottomInset: extraBottomInset))
    }
}

#Preview("Warning") {
    @Previewable @State var message: DSToastMessage? = DSToastMessage(
        icon: IconKit.errorFill,
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
