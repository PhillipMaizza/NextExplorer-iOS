import ComposableArchitecture
import Foundation

/// The accounts whose cached data is being wiped. An account is listed before its wipe starts and
/// unlisted only once a second pass, after its effects were cancelled, has run: a writer that
/// landed in between, or an app kill before that pass, is cleaned up by the pass at the next launch.
struct PendingAccountWipes: Sendable {
    var accounts: @Sendable () -> [String]
    var add: @Sendable (_ accountID: String) -> Void
    var remove: @Sendable (_ accountID: String) -> Void
}

extension PendingAccountWipes {
    private enum Constants {
        static let defaultsKey = "pendingAccountCacheWipes"
    }

    /// Persisted in `defaults`, so the list survives a kill.
    static func persisted(in defaults: UserDefaults = .standard) -> PendingAccountWipes {
        let lock = NSLock()
        nonisolated(unsafe) let defaults = defaults
        return PendingAccountWipes(
            accounts: { lock.withLock { defaults.stringArray(forKey: Constants.defaultsKey) ?? [] } },
            add: { accountID in
                lock.withLock {
                    var ids = defaults.stringArray(forKey: Constants.defaultsKey) ?? []
                    if !ids.contains(accountID) {
                        ids.append(accountID)
                    }
                    defaults.set(ids, forKey: Constants.defaultsKey)
                }
            },
            remove: { accountID in
                lock.withLock {
                    let ids = (defaults.stringArray(forKey: Constants.defaultsKey) ?? []).filter { $0 != accountID }
                    defaults.set(ids, forKey: Constants.defaultsKey)
                }
            }
        )
    }

    static func inMemory() -> PendingAccountWipes {
        let ids = LockIsolated<[String]>([])
        return PendingAccountWipes(
            accounts: { ids.value },
            add: { accountID in ids.withValue {
                if !$0.contains(accountID) {
                    $0.append(accountID)
                }
            } },
            remove: { accountID in ids.withValue { $0.removeAll { $0 == accountID } } }
        )
    }
}

extension PendingAccountWipes: DependencyKey {
    static var liveValue: PendingAccountWipes {
        .persisted()
    }

    static var testValue: PendingAccountWipes {
        .inMemory()
    }
}

extension DependencyValues {
    var pendingAccountWipes: PendingAccountWipes {
        get { self[PendingAccountWipes.self] }
        set { self[PendingAccountWipes.self] = newValue }
    }
}
