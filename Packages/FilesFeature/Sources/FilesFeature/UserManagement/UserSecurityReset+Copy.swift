import ComposableArchitecture
import CoreModels
import DesignSystem
import Foundation
import Localization
import SwiftUI

extension UserSecurityReset {
    /// Toast shown once the server has applied the reset.
    var toast: String {
        switch self {
        case .lock: L10n.UserManagement.toastUnlocked
        case .twoFactor: L10n.UserManagement.toastTwoFactorReset
        case .passkeys: L10n.UserManagement.toastPasskeysRemoved
        }
    }

    var actionTitle: String {
        switch self {
        case .lock: L10n.UserDetail.lockRelease
        case .twoFactor: L10n.UserDetail.twoFactorReset
        case .passkeys: L10n.UserDetail.passkeysRemove
        }
    }

    /// Confirmation title; a lock release never asks, so it has none.
    var confirmTitle: String? {
        switch self {
        case .lock: nil
        case .twoFactor: L10n.UserDetail.resetTwoFactorTitle
        case .passkeys: L10n.UserDetail.resetPasskeysTitle
        }
    }

    func confirmMessage(for name: String) -> String? {
        switch self {
        case .lock: nil
        case .twoFactor: L10n.UserDetail.resetTwoFactorMessage(name)
        case .passkeys: L10n.UserDetail.resetPasskeysMessage(name)
        }
    }
}

/// One account recovery row of the user detail, shared by the iOS Security tab and the Mac form.
/// A lock and a second factor only appear while there is something to reset; the server does not
/// say who has passkeys, so that row is always there.
struct UserRecoveryRow: Identifiable {
    let reset: UserSecurityReset
    let icon: Image
    let title: String
    let subtitle: String

    var id: UserSecurityReset {
        reset
    }

    static func rows(for user: User) -> [UserRecoveryRow] {
        var rows: [UserRecoveryRow] = []
        if let until = user.lockedUntil {
            rows.append(UserRecoveryRow(
                reset: .lock,
                icon: IconKit.lock,
                title: L10n.UserDetail.lockTitle,
                subtitle: L10n.UserDetail.lockedUntil(until.formatted(date: .abbreviated, time: .shortened))
            ))
        }
        if user.twoFactorEnabled {
            rows.append(UserRecoveryRow(
                reset: .twoFactor,
                icon: IconKit.shield,
                title: L10n.UserDetail.twoFactorTitle,
                subtitle: L10n.UserDetail.twoFactorOn
            ))
        }
        rows.append(UserRecoveryRow(
            reset: .passkeys,
            icon: IconKit.key,
            title: L10n.UserDetail.passkeysTitle,
            subtitle: L10n.UserDetail.passkeysSubtitle
        ))
        return rows
    }
}

/// The confirmation for a two factor or passkey reset. Releasing a lock never presents it.
@MainActor
func securityResetAlert(store: StoreOf<UserManagementFeature>) -> DSAlertSheet {
    let reset = store.securityResetToConfirm
    return DSAlertSheet(
        icon: IconKit.shield,
        title: reset?.confirmTitle ?? "",
        message: reset.flatMap { $0.confirmMessage(for: store.detailUser?.displayLabel ?? "") },
        confirmTitle: reset?.actionTitle ?? "",
        dismissTitle: L10n.Common.cancel,
        role: .destructive,
        closeAccessibilityLabel: L10n.Common.close,
        onConfirm: { store.send(.securityResetConfirmed) },
        onDismiss: { store.send(.securityResetCancelled) }
    )
}
