import CoreModels
import SwiftUI

/// A brief message overlaid at the bottom of the screen: either a self dismissing warning
/// (e.g. "Unsupported file type") or a persistent progress indicator (e.g. "Extracting…")
/// that stays until whoever's driving it clears the binding themselves.
public struct DSToastMessage: Equatable, Identifiable {
    public let id: String
    public let icon: Image?
    public let text: String
    public let detail: String?
    public let tint: Color
    public let isPersistent: Bool
    /// Distinguishes a success confirmation from a warning: both are brief and
    /// auto dismissing, but only one should play a success haptic instead of an error one.
    let isSuccess: Bool
    /// An optional trailing action button (e.g. "Open"). Not part of `Equatable`, so a closure
    /// here doesn't need to conform.
    public let actionTitle: String?
    public let action: (() -> Void)?
    public let transfer: Transfer?

    public struct Transfer {
        public let fraction: Double?
        public let fileName: String?
        public let timeLeft: String?
        public let cancelTitle: String
        public let cancel: () -> Void
    }

    /// A brief, auto dismissing warning style toast.
    public init(icon: Image, text: String) {
        // A fresh id per instance, not derived from `text`: `.task(id:)` below only restarts
        // the auto dismiss timer when `id` changes, so two identical text toasts triggered
        // back to back (e.g. tapping two different unsupported files in a row) need distinct
        // ids or the second tap's toast silently inherits whatever time was left on the
        // first one's timer instead of a fresh window.
        id = UUID().uuidString
        self.icon = icon
        self.text = text
        detail = nil
        tint = .negativeText
        isPersistent = false
        isSuccess = false
        actionTitle = nil
        action = nil
        transfer = nil
    }

    /// A persistent progress toast: no auto dismiss timer at all, since there's no fixed
    /// duration for e.g. an archive extract/compress to know in advance. Stays until the
    /// caller's own state (driving the binding) clears it.
    public static func progress(_ text: String) -> DSToastMessage {
        DSToastMessage(progressText: text)
    }

    /// A brief, auto dismissing success confirmation (e.g. "Saved to Documents"). `actionTitle`/
    /// `action` add a trailing button (e.g. "Open"): omit both for a plain confirmation.
    public static func success(
        _ text: String,
        detail: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> DSToastMessage {
        DSToastMessage(
            successText: text,
            detail: detail,
            actionTitle: actionTitle,
            action: action
        )
    }

    /// A brief, auto dismissing failure toast (warning icon in `.negativeText`) with an
    /// optional trailing action: e.g. "Retry" on a copy/move that didn't go through.
    public static func failure(
        _ text: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> DSToastMessage {
        DSToastMessage(
            failureText: text,
            actionTitle: actionTitle,
            action: action
        )
    }

    public static func transfer(
        _ text: String,
        id: String,
        icon: Image,
        fraction: Double?,
        fileName: String?,
        timeLeft: String?,
        actionTitle: String,
        action: @escaping () -> Void,
        cancelTitle: String,
        cancel: @escaping () -> Void
    ) -> DSToastMessage {
        DSToastMessage(
            transferText: text,
            id: id,
            icon: icon,
            actionTitle: actionTitle,
            action: action,
            transfer: Transfer(
                fraction: fraction,
                fileName: fileName,
                timeLeft: timeLeft,
                cancelTitle: cancelTitle,
                cancel: cancel
            )
        )
    }

    /// Keyed by its text, not a fresh id: callers rebuild it from state on every render, and a new
    /// id each time would restart the presenter swap forever. With no timer, reuse is harmless.
    private init(progressText: String) {
        id = Self.progressIDPrefix + progressText
        icon = nil
        text = progressText
        detail = nil
        tint = .tertiaryDS
        isPersistent = true
        isSuccess = false
        actionTitle = nil
        action = nil
        transfer = nil
    }

    private init(
        transferText: String,
        id: String,
        icon: Image,
        actionTitle: String,
        action: @escaping () -> Void,
        transfer: Transfer
    ) {
        self.id = id
        self.icon = icon
        text = transferText
        detail = nil
        tint = .accentText
        isPersistent = true
        isSuccess = false
        self.actionTitle = actionTitle
        self.action = action
        self.transfer = transfer
    }

    private init(successText: String, detail: String?, actionTitle: String?, action: (() -> Void)?) {
        id = UUID().uuidString
        icon = IconKit.checkmarkCircleFill
        text = successText
        self.detail = detail
        tint = .positiveText
        isPersistent = false
        isSuccess = true
        self.actionTitle = actionTitle
        self.action = action
        transfer = nil
    }

    private init(failureText: String, actionTitle: String?, action: (() -> Void)?) {
        id = UUID().uuidString
        icon = IconKit.errorFill
        text = failureText
        detail = nil
        tint = .negativeText
        isPersistent = false
        isSuccess = false
        self.actionTitle = actionTitle
        self.action = action
        transfer = nil
    }

    private static let progressIDPrefix = "progress:"
    static let autoDismissDelay: Duration = .seconds(4.5)

    public static func == (lhs: DSToastMessage, rhs: DSToastMessage) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text && lhs.detail == rhs.detail
            && lhs.transfer?.fraction == rhs.transfer?.fraction
            && lhs.transfer?.fileName == rhs.transfer?.fileName
            && lhs.transfer?.timeLeft == rhs.transfer?.timeLeft
    }
}
