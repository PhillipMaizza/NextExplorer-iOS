import AuthClient
import AuthFeature
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Foundation
import SwiftUI

extension AppFeature {
    func reduceLock(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .appLeft:
            guard case .authenticated = state.destination else { return .none }
            state.leftAt = date.now
            return lockDue(&state, away: .zero)
        case .appReturned:
            guard let leftAt = state.leftAt else { return .none }
            state.leftAt = nil
            return lockDue(&state, away: .seconds(abs(date.now.timeIntervalSince(leftAt))))
        case let .lockShown(account):
            showLock(&state, account: account)
            return .none
        case let .accountsLocked(locked):
            return finishLocking(locked)
        case let .destination(.locked(.delegate(.signedIn(user, serverURL)))):
            return lockSignedIn(&state, user: user, serverURL: serverURL)
        case .destination(.locked(.delegate(.signOutRequested))):
            return signOutLocked(state)
        case let .destination(.locked(.delegate(.switchAccount(accountID)))):
            let authClient = authClient
            return .run { send in
                guard let credentials = try? await authClient.switchAccount(accountID) else { return }
                await send(.activateAccount(credentials))
            }
        case let .lockedAccountSignedOut(next):
            guard let next else {
                return teardownToLogin(&state, removesClientCertificates: true)
            }
            return .merge(.send(.activateAccount(next)), pruneClientCertificates())
        default:
            return .none
        }
    }

    private func lockDue(_ state: inout State, away: Duration) -> Effect<Action> {
        let due = Set(
            state.accounts
                .filter { !$0.isLocked && $0.requireSignIn?.lockAfter.locks(after: away) == true }
                .map(\.id)
        )
        guard !due.isEmpty else { return .none }
        let authClient = authClient
        let lockDue = Effect<Action>.run { send in
            let locked = await (try? authClient.lockSessions { due.contains($0.accountID) }) ?? []
            await send(.accountsLocked(locked))
        }
        guard let current = state.currentAccountID, due.contains(current),
              var account = state.accounts.first(where: { $0.id == current })
        else {
            return lockDue
        }
        account.isLocked = true
        return .concatenate(
            stopOfflineWork(leaving: current),
            .send(.lockShown(account)),
            lockDue
        )
    }

    private func showLock(_ state: inout State, account: AccountSummary) {
        state.clearAccountSharedState()
        state.$downloadScope.withLock { $0 = "" }
        state.addAccount = nil
        state.pendingAddedAccount = nil
        state.didAuthenticateFromLogin = false
        thumbnailCache.clearMemory()
        withAnimation(DSMotion.contentReveal) {
            state.destination = .locked(LockFeature.State(account: account))
        }
    }

    private func finishLocking(_ locked: [SessionCredentials]) -> Effect<Action> {
        let accountCacheWipe = accountCacheWipe
        let authClient = authClient
        return .merge(
            refreshAccounts,
            .run { _ in
                await Self.endLockedSessions(locked, authClient: authClient, accountCacheWipe: accountCacheWipe)
            }
        )
    }

    static func endLockedSessions(
        _ locked: [SessionCredentials],
        authClient: AuthClient,
        accountCacheWipe: AccountCacheWipe
    ) async {
        for credentials in locked where credentials.requireSignIn?.shouldKeepOfflineFiles == false {
            accountCacheWipe.wipeLocked(credentials.accountID)
        }
        for credentials in locked {
            await authClient.endSession(credentials)
        }
    }

    private func lockSignedIn(_ state: inout State, user: User, serverURL: URL) -> Effect<Action> {
        guard case let .locked(lock) = state.destination else { return .none }
        let accountID = SessionCredentials.accountID(serverURL: serverURL, username: user.username)
        guard accountID == lock.account.id else {
            return refuseOtherAccount(
                accountID,
                lockedID: lock.account.id,
                knownIDs: Set(state.accounts.map(\.id))
            )
        }
        return unlock(&state, user: user, serverURL: serverURL, accountID: accountID)
    }

    private func signOutLocked(_ state: State) -> Effect<Action> {
        guard case let .locked(lock) = state.destination else { return .none }
        let accountCacheWipe = accountCacheWipe
        let authClient = authClient
        let accountID = lock.account.id
        return .run { send in
            do {
                let next = try await accountCacheWipe.signOut(accountID, authClient: authClient)
                await send(.lockedAccountSignedOut(next))
            } catch {
                await send(.destination(.locked(.signOutFailed)))
            }
        }
    }

    private func unlock(
        _ state: inout State,
        user: User,
        serverURL: URL,
        accountID: String
    ) -> Effect<Action> {
        if state.sessionDidExpire {
            state.$sessionDidExpire.withLock { $0 = false }
        }
        CacheAccountScope.set(accountID)
        pendingAccountWipes.remove(accountID)
        let recordOwner = beginDownloadScope(
            &state,
            accountID: accountID,
            serverURL: serverURL,
            userID: user.id
        )
        withAnimation(DSMotion.contentReveal) {
            state.destination = .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user))
        }
        return .merge(refreshAccounts, recordOwner, finishAccountWipes)
    }

    private func refuseOtherAccount(
        _ accountID: String,
        lockedID: String,
        knownIDs: Set<String>
    ) -> Effect<Action> {
        let authClient = authClient
        return .concatenate(
            .run { send in
                if !knownIDs.contains(accountID) {
                    _ = try? await authClient.removeAccount(accountID)
                }
                _ = try? await authClient.switchAccount(lockedID)
                await send(.destination(.locked(.otherAccountRefused)))
            },
            refreshAccounts
        )
    }
}
