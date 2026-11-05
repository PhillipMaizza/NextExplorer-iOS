import Foundation
#if os(iOS)
    import UIKit
#endif

/// Holds a UIKit background task assertion around a piece of async work, so an in-flight offline sync
/// keeps running through the OS-granted execution window (typically ~30s) after the app is
/// backgrounded, instead of being suspended the instant the user leaves. Anything not finished in that
/// window is picked up by the next auto-sync when the app returns.
///
/// A true "downloads continue indefinitely while suspended" experience would need a background
/// `URLSession` plus app relaunch handling; this is the bounded, self-contained step toward it.
enum BackgroundActivity {
    /// A user's upload or download: on the Mac the system must not idle sleep or nap the app
    /// partway through it, as Safari keeps a download going. iOS runs it as is; its transfer
    /// queues already resume when the app comes back.
    static func whileTransferring(name: String, _ work: @Sendable () async -> Void) async {
        #if os(macOS)
            await run(name: name, work)
        #else
            await work()
        #endif
    }

    static func run<T: Sendable>(name: String, _ work: @Sendable () async -> T) async -> T {
        #if os(macOS)
            let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: name)
            defer { ProcessInfo.processInfo.endActivity(activity) }
            return await work()
        #else
            let assertion = Assertion()
            await assertion.begin(name: name)
            let result = await work()
            await assertion.end()
            return result
        #endif
    }

    #if os(iOS)

        /// Owns the task identifier and guarantees it is ended exactly once: on completion, or from the
        /// expiration handler if the OS reclaims the window first (ending it there avoids the app being
        /// killed for overrunning).
        private actor Assertion {
            private var id: UIBackgroundTaskIdentifier = .invalid

            func begin(name: String) async {
                id = await MainActor.run {
                    UIApplication.shared.beginBackgroundTask(withName: name) {
                        Task { await self.end() }
                    }
                }
            }

            func end() async {
                guard id != .invalid else { return }
                let current = id
                id = .invalid
                await MainActor.run { UIApplication.shared.endBackgroundTask(current) }
            }
        }
    #endif
}
