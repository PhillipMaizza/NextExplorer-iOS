import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private typealias Metrics = UserDetailMetrics

// MARK: Profile tab

/// General info form + roles card, plus the Danger Zone (remove user) unless the admin is
/// viewing their own account.
struct ProfileTabView: View {
    @Bindable var store: StoreOf<UserManagementFeature>
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            Card(L10n.UserDetail.sectionGeneralInfo) {
                LabeledField(L10n.UserDetail.profileDisplayNameField, uppercased: false) {
                    DSTextField(L10n.UserDetail.profileDisplayNamePlaceholder, text: binding(\.editDisplayName, UserManagementFeature.Action.editDisplayNameChanged))
                        .autocorrectionDisabled()
                }
                LabeledField(L10n.UserDetail.profileUsernameField, error: store.isProfileDirty ? store.profileUsernameError : nil, uppercased: false) {
                    DSTextField(L10n.UserDetail.profileUsernamePlaceholder, text: binding(\.editUsername, UserManagementFeature.Action.editUsernameChanged))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledField(L10n.UserDetail.profileEmailField, error: store.isProfileDirty ? store.profileEmailError : nil, uppercased: false) {
                    DSTextField(L10n.UserDetail.profileEmailPlaceholder, text: binding(\.editEmail, UserManagementFeature.Action.editEmailChanged))
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                DSButton(L10n.UserDetail.profileSave, style: .primary, isLoading: store.isSavingProfile) {
                    store.send(.saveProfileTapped)
                }
                .disabled(!store.isProfileSaveEnabled)
                .padding(.top, .space4)
            }

            Card(L10n.UserDetail.sectionRoles) {
                HStack(alignment: .top, spacing: .space8) {
                    IconKit.shield
                        .resizable().scaledToFit()
                        .foregroundStyle(Color.accent)
                        .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                        .padding(.top, .space2)
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(L10n.UserDetail.roleAdmin).type(.body2(.semibold), style: .primary(for: .label))
                        Text(L10n.UserDetail.roleAdminSubtitle)
                            .type(.body3(.regular), style: .secondary)
                    }
                    Spacer(minLength: .space8)
                }
                if store.isUpdatingRoles {
                    DSSpinner().frame(maxWidth: .infinity, alignment: .leading)
                } else if user.isAdmin {
                    // No "Revoke Admin": the backend refuses to demote any administrator
                    // (`PATCH /api/users/:id` 400s with "Demotion of admin is not allowed."), so
                    // offering the action would only ever produce an error.
                    HStack(alignment: .firstTextBaseline, spacing: .space4) {
                        IconKit.info
                            .resizable().scaledToFit()
                            .foregroundStyle(Color.tertiaryDS)
                            .frame(width: Metrics.lockedInfoIconSize, height: Metrics.lockedInfoIconSize)
                        Text(L10n.UserDetail.roleAdminLocked)
                            .type(.caption(.regular), style: .tertiary)
                        Spacer(minLength: 0)
                    }
                } else {
                    DSButton(L10n.UserDetail.roleGrantAdmin, style: .secondary) { store.send(.grantAdminTapped) }
                }
            }

            if !store.isViewingOwnAccount {
                dangerZone
            }
        }
    }

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            Text(L10n.UserDetail.dangerZoneTitle).type(.body2(.semibold), style: .error)
            Text(L10n.UserDetail.dangerZoneSubtitle)
                .type(.body3(.regular), style: .secondary)
            DSButton(L10n.UserDetail.dangerZoneRemoveUser, icon: IconKit.delete, style: .failure) {
                store.send(.deleteUserTapped(user))
            }
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).fill(Color.negative.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                .strokeBorder(Color.negative.opacity(0.3), lineWidth: .borderWidthHairline)
        )
    }

    private func binding(
        _ keyPath: KeyPath<UserManagementFeature.State, String>,
        _ action: @escaping (String) -> UserManagementFeature.Action
    ) -> Binding<String> {
        Binding(get: { store.state[keyPath: keyPath] }, set: { store.send(action($0)) })
    }
}

// MARK: Security tab

/// Local password state (set/reset) and the linked SSO providers, both read-only summaries
/// with a single action.
struct SecurityTabView: View {
    let store: StoreOf<UserManagementFeature>
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            Card(L10n.UserDetail.sectionLocalPassword) {
                HStack(alignment: .top, spacing: .space8) {
                    IconKit.key
                        .resizable().scaledToFit()
                        .foregroundStyle(Color.secondaryDS)
                        .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                        .padding(.top, .space2)
                    Text(user.hasLocalPassword
                        ? L10n.UserDetail.passwordHasLocal
                        : L10n.UserDetail.passwordSSOOnly)
                        .type(.body3(.regular), style: .secondary)
                    Spacer(minLength: .space8)
                }
                DSButton(user.hasLocalPassword ? L10n.UserDetail.passwordReset : L10n.UserDetail.passwordSet, style: .secondary) {
                    store.send(.setPasswordTapped)
                }
            }

            Card(L10n.UserDetail.sectionSSO) {
                if user.oidcMethods.isEmpty {
                    HStack(spacing: .space8) {
                        IconKit.cloud
                            .resizable().scaledToFit()
                            .foregroundStyle(Color.tertiaryDS)
                            .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                        Text(L10n.UserDetail.ssoNone).type(.body3(.regular), style: .secondary)
                    }
                } else {
                    ForEach(Array(user.oidcMethods.enumerated()), id: \.offset) { _, method in
                        HStack(spacing: .space8) {
                            IconKit.cloud
                                .resizable().scaledToFit()
                                .foregroundStyle(Color.secondaryDS)
                                .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                            Text(method.provider ?? L10n.UserDetail.ssoBadge).type(.body2(.regular), style: .primary(for: .label))
                            Spacer()
                            Text(L10n.UserDetail.ssoLinked).type(.caption(.semibold), style: .success)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Volumes tab

/// Assigned volumes list (edit / remove each) plus the assign action, gated behind the
/// `USER_VOLUMES` server feature by the parent.
struct VolumesTabView: View {
    let store: StoreOf<UserManagementFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            Card(L10n.UserDetail.sectionAssignedVolumes) {
                if store.volumesPhase == .loading {
                    DSSpinner().frame(maxWidth: .infinity, alignment: .center).padding(.vertical, .space8)
                } else if store.volumes.isEmpty {
                    VStack(spacing: .space4) {
                        Text(L10n.UserDetail.volumesNone).type(.body3(.regular), style: .secondary)
                        Text(L10n.UserDetail.volumesNoneSubtitle).type(.caption(.regular), style: .tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .space8)
                } else {
                    ForEach(store.volumes) { volume in
                        volumeRow(volume)
                    }
                }
                DSButton(L10n.UserDetail.volumesAssign, icon: IconKit.plus, style: .secondary) {
                    store.send(.addVolumeTapped)
                }
                .padding(.top, .space4)
            }

            Text(L10n.UserDetail.volumesFootnote)
                .type(.body3(.regular), style: .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Metrics.cardPadding)
                .background(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).fill(Color.accent.opacity(0.08)))
        }
    }

    private func volumeRow(_ volume: UserVolume) -> some View {
        HStack(spacing: .space12) {
            IconKit.folder
                .resizable().scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
            VStack(alignment: .leading, spacing: .space2) {
                Text(volume.label).type(.body2(.semibold), style: .primary(for: .label)).lineLimit(1)
                Text(volume.path).type(.caption(.regular), style: .tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: .space8)
            AccessModeBadge(mode: volume.accessMode)
            Button { store.send(.editVolumeTapped(volume)) } label: {
                IconKit.rename.resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(L10n.UserDetail.volumeEditAccessibility(volume.label))
            Button { store.send(.removeVolumeTapped(volume)) } label: {
                IconKit.delete.resizable().scaledToFit()
                    .foregroundStyle(Color.negative)
                    .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(L10n.UserDetail.volumeRemoveAccessibility(volume.label))
        }
        .padding(.vertical, .space8)
    }
}
