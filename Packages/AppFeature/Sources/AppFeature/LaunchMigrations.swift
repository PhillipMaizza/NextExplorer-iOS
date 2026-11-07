import AuthClient

/// Work the app does once at launch, before any screen reads stored data.
public enum LaunchMigrations {
    /// The steps and the hold on keychain reads, replaceable in tests.
    struct Steps: Sendable {
        var begin: @Sendable () -> Void
        var sharedGroup: @Sendable () -> Void
        var legacyMac: @Sendable () -> Void
        var finish: @Sendable () -> Void

        static let live = Steps(
            begin: { KeychainMigration.begin() },
            sharedGroup: { KeychainMigration.sharedGroup() },
            legacyMac: { KeychainMigration.legacyMac() },
            finish: { KeychainMigration.finish() }
        )
    }

    /// Moves keychain items an older release stored where the Share Extension can't see them (and,
    /// on the Mac, in the legacy file keychain), so a signed in user never meets "sign in first"
    /// after updating. It runs off the main thread; keychain reads wait for it, so the first
    /// session read never sees a half moved keychain.
    public static func start() {
        _ = start(steps: .live)
        Task.detached(priority: .utility) {
            LegacyCacheCleanup.runIfNeeded()
            PendingAccountWipeRecovery.runAtLaunch()
        }
    }

    @discardableResult
    static func start(steps: Steps) -> Task<Void, Never> {
        steps.begin()
        return Task.detached(priority: .userInitiated) {
            defer { steps.finish() }
            steps.sharedGroup()
            steps.legacyMac()
        }
    }
}
