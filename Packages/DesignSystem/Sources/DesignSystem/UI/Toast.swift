import SwiftUI

private enum Constants {
    static let horizontalPadding: CGFloat = .space16
    static let verticalPadding: CGFloat = .space12
    static let spacing: CGFloat = .space8
    static let iconSize: CGFloat = .iconSmall
    static let bottomInset: CGFloat = .space48
    static let autoDismissDelay: Duration = .seconds(2.5)
    static let animationDuration: Double = 0.3
}

/// A brief message overlaid at the bottom of the screen — either a self-dismissing warning
/// (e.g. "Unsupported file type") or a persistent progress indicator (e.g. "Extracting…")
/// that stays until whoever's driving it clears the binding themselves.
public struct DSToastMessage: Equatable, Identifiable {
    public let id: String
    public let icon: Image?
    public let text: String
    public let backgroundColor: Color
    public let isPersistent: Bool

    /// A brief, auto-dismissing warning-style toast.
    public init(icon: Image, text: String) {
        // A fresh id per instance, not derived from `text` — `.task(id:)` below only restarts
        // the auto-dismiss timer when `id` changes, so two identical-text toasts triggered
        // back-to-back (e.g. tapping two different unsupported files in a row) need distinct
        // ids or the second tap's toast silently inherits whatever time was left on the
        // first one's timer instead of a fresh window.
        self.id = UUID().uuidString
        self.icon = icon
        self.text = text
        self.backgroundColor = .negative
        self.isPersistent = false
    }

    /// A persistent progress toast — no auto-dismiss timer at all, since there's no fixed
    /// duration for e.g. an archive extract/compress to know in advance. Stays until the
    /// caller's own state (driving the binding) clears it.
    public static func progress(_ text: String) -> DSToastMessage {
        DSToastMessage(progressText: text)
    }

    private init(progressText: String) {
        self.id = UUID().uuidString
        self.icon = nil
        self.text = progressText
        self.backgroundColor = .secondaryDS
        self.isPersistent = true
    }

    public static func == (lhs: DSToastMessage, rhs: DSToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

private struct DSToastModifier: ViewModifier {
    @Binding var message: DSToastMessage?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                HStack(spacing: Constants.spacing) {
                    if let icon = message.icon {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: Constants.iconSize, height: Constants.iconSize)
                    } else {
                        ProgressView()
                            .tint(Color.primaryInverted)
                    }
                    Text(message.text).type(.body2(.semibold))
                }
                .foregroundStyle(Color.primaryInverted)
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.vertical, Constants.verticalPadding)
                .background(Capsule().fill(message.backgroundColor))
                .padding(.bottom, Constants.bottomInset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message.id) {
                    guard !message.isPersistent else { return }
                    try? await Task.sleep(for: Constants.autoDismissDelay)
                    self.message = nil
                }
            }
        }
        .animation(.spring(duration: Constants.animationDuration), value: message)
        // Persistent progress toasts (e.g. "Extracting\u{2026}") aren't errors — only the
        // auto-dismissing warning style should buzz.
        .hapticFeedback(.warning, trigger: message?.id) { _, newValue in
            newValue != nil && message?.isPersistent == false
        }
    }
}

public extension View {
    /// Shows `message` as a bottom toast while non-`nil`, auto-clearing the binding after a
    /// few seconds. Set `message` to `nil` yourself to dismiss early.
    func dsToast(_ message: Binding<DSToastMessage?>) -> some View {
        modifier(DSToastModifier(message: message))
    }
}

#Preview("Warning") {
    @Previewable @State var message: DSToastMessage? = DSToastMessage(
        icon: IconKit.exclamationmarkTriangle,
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
