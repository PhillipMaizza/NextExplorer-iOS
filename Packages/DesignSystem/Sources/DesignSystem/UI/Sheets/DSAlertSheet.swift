import SwiftUI

private enum Constants {
    static let contentSpacing: CGFloat = .space16
    static let contentPadding: CGFloat = .space24
    static let buttonSpacing: CGFloat = .space12
    static let messageLineSpacing: CGFloat = .space4
    static let titleLineLimit = 2
}

/// The app's confirmation prompt, presented with `.sheet(isPresented:) { DSAlertSheet(...) }`.
/// Replaces the native `.alert` for deliberate actions (sign out, discard, delete): a
/// `DSDynamicHeightSheet` card whose header icon + title and optional message sit in the
/// scrolling `content`, and whose footer stacks the confirm action on top, an optional
/// `neutralTitle` middle action, then the dismiss.
///
/// It disables interactive (swipe) dismissal: like an alert it only closes through one of
/// its own buttons, so give the presenting binding a no op setter and derive its getter from
/// feature state. Like a system alert, VoiceOver starts on the title and message, Escape
/// dismisses, and Return confirms a standard prompt (never a destructive one). While `isConfirmLoading` is true every
/// control but the confirm spinner
/// locks. `closeAccessibilityLabel` / `dismissTitle` default to English; localized call sites
/// pass their own `L10n` strings so DesignSystem stays free of an app copy dependency.
public struct DSAlertSheet: View {
    /// Standard prompts tint the header accent and confirm in `.primary`; `.destructive`
    /// tints the header icon + title `.negative` and confirms in `.failure`.
    public enum Role {
        case standard
        case destructive

        var headerTint: Color {
            self == .destructive ? .negative : .accent
        }

        var confirmStyle: DSButtonStyle {
            self == .destructive ? .failure : .primary
        }
    }

    private let icon: Image
    let title: String
    let message: String?
    let confirmTitle: String
    let dismissTitle: String
    let neutralTitle: String?
    let role: Role
    let isConfirmLoading: Bool
    private let closeAccessibilityLabel: String
    let onConfirm: () -> Void
    let onNeutral: (() -> Void)?
    let onDismiss: () -> Void
    @AccessibilityFocusState private var isPromptFocused: Bool

    public init(
        icon: Image,
        title: String,
        message: String? = nil,
        confirmTitle: String,
        dismissTitle: String = "Cancel",
        neutralTitle: String? = nil,
        role: Role = .standard,
        isConfirmLoading: Bool = false,
        closeAccessibilityLabel: String = "Close",
        onConfirm: @escaping () -> Void,
        onNeutral: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.dismissTitle = dismissTitle
        self.neutralTitle = neutralTitle
        self.role = role
        self.isConfirmLoading = isConfirmLoading
        self.closeAccessibilityLabel = closeAccessibilityLabel
        self.onConfirm = onConfirm
        self.onNeutral = onNeutral
        self.onDismiss = onDismiss
    }

    private var hasNeutralAction: Bool {
        neutralTitle != nil && onNeutral != nil
    }

    public var body: some View {
        DSDynamicHeightSheet {
            VStack(alignment: .leading, spacing: Constants.contentSpacing) {
                DSSheetHeader(
                    icon: icon,
                    tint: role.headerTint,
                    closeAccessibilityLabel: closeAccessibilityLabel,
                    onClose: onDismiss
                )
                // While the confirm action runs, its spinner is the only live control: the
                // close chip locks so the prompt can't be dismissed out from under the work.
                .disabled(isConfirmLoading)

                prompt
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Constants.contentPadding)
            .padding(.vertical, Constants.contentPadding)
        } footer: {
            DSSheetFooter {
                VStack(spacing: Constants.buttonSpacing) {
                    DSButton(confirmTitle, style: role.confirmStyle, isLoading: isConfirmLoading, action: onConfirm)
                        // As a system alert: Return takes the safe default, never a destructive action.
                        .keyboardShortcut(role == .standard ? .defaultAction : nil)
                    if let neutralTitle, let onNeutral {
                        DSButton(neutralTitle, style: .secondary, action: onNeutral)
                            .disabled(isConfirmLoading)
                    }
                    DSButton(dismissTitle, style: hasNeutralAction ? .ghost : .secondary, action: onDismiss)
                        .keyboardShortcut(.cancelAction)
                        .disabled(isConfirmLoading)
                }
            }
        }
        .interactiveDismissDisabled()
        .task { isPromptFocused = true }
    }

    /// The title and message read as one, first, the way VoiceOver opens a system alert.
    private var prompt: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            Text(title)
                .type(.headline3)
                .foregroundColor(role.headerTint)
                .lineLimit(Constants.titleLineLimit)

            if let message {
                Text(message)
                    .type(.body2(.regular), style: .secondary)
                    .lineSpacing(Constants.messageLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($isPromptFocused)
    }
}

#Preview("Standard") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DSAlertSheet(
            icon: IconKit.signOut,
            title: "Sign Out?",
            message: "You'll need to sign in again to access your files.",
            confirmTitle: "Log Out",
            onConfirm: {},
            onDismiss: {}
        )
    }
}

#Preview("Destructive") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DSAlertSheet(
            icon: IconKit.delete,
            title: "Delete “vacation.jpg”?",
            message: "This can't be undone.",
            confirmTitle: "Delete",
            role: .destructive,
            onConfirm: {},
            onDismiss: {}
        )
    }
}

#Preview("Three actions") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DSAlertSheet(
            icon: IconKit.warning,
            title: "Replace items?",
            message: "\"report.pdf\" already exists in this folder.",
            confirmTitle: "Replace",
            neutralTitle: "Keep Both",
            role: .destructive,
            onConfirm: {},
            onNeutral: {},
            onDismiss: {}
        )
    }
}

#Preview("Loading") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DSAlertSheet(
            icon: IconKit.signOut,
            title: "Sign Out?",
            message: "You'll need to sign in again to access your files.",
            confirmTitle: "Log Out",
            isConfirmLoading: true,
            onConfirm: {},
            onDismiss: {}
        )
    }
}
