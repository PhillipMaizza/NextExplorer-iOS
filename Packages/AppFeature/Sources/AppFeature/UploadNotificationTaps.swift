import ComposableArchitecture
import Foundation

/// Taps on an "upload finished" notification, from the notification center's delegate to the app's
/// store. Buffered, because a tap that launches the app arrives before the store is listening.
public enum UploadNotificationTaps {
    public struct Tap: Equatable, Sendable {
        public let accountID: String
        /// The folder the files went to.
        public let folder: String

        public init(accountID: String, folder: String) {
            self.accountID = accountID
            self.folder = folder
        }
    }

    private static let channel = AsyncStream<Tap>.makeStream(bufferingPolicy: .bufferingNewest(1))

    public static var taps: AsyncStream<Tap> {
        channel.stream
    }

    static func send(_ tap: Tap) {
        channel.continuation.yield(tap)
    }
}

public extension AppFeature {
    /// A tapped notification's folder, held until the app is signed in to that account.
    struct PendingUploadFolder: Equatable, Sendable {
        let tap: UploadNotificationTaps.Tap
        /// A switch to the tap's account was already asked for, so a second mismatch gives up.
        var hasRequestedSwitch = false
    }
}

/// Opens the folder of a tapped upload notification once the tab shell of its account is up: right
/// away when that account is active, after a switch when it is another signed in one, and not at
/// all when it is signed out (the app just opens).
struct UploadFolderRouting: Reducer {
    typealias State = AppFeature.State
    typealias Action = AppFeature.Action

    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .uploadNotificationTapped(tap):
            state.pendingUploadFolder = AppFeature.PendingUploadFolder(tap: tap)
            return openPendingFolder(&state)

        case .destination(.authenticated(.mainTab(.observeConnectivity))):
            // The tab shell just mounted (any sign in or account switch ends here).
            return openPendingFolder(&state)

        default:
            return .none
        }
    }

    private func openPendingFolder(_ state: inout State) -> Effect<Action> {
        guard let pending = state.pendingUploadFolder, let current = state.currentAccountID else { return .none }
        if current == pending.tap.accountID {
            state.pendingUploadFolder = nil
            return .send(.destination(.authenticated(.mainTab(.goToFolderRequested(pending.tap.folder)))))
        }
        guard !pending.hasRequestedSwitch, state.accounts.contains(where: { $0.id == pending.tap.accountID }) else {
            state.pendingUploadFolder = nil
            return .none
        }
        state.pendingUploadFolder?.hasRequestedSwitch = true
        return .send(.destination(.authenticated(.mainTab(.delegate(.switchAccount(pending.tap.accountID))))))
    }
}
