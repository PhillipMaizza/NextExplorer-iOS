import Foundation

/// A URLSession that is swapped for a brand new one whenever a client certificate changes.
/// Flushing or resetting a session is not enough: it keeps its TLS session cache, so the next
/// connection resumes the old handshake and the server still sees the identity that was just
/// removed or replaced. A new session starts with an empty cache and handshakes from scratch.
///
/// `@unchecked Sendable`: `current` is only read and swapped behind `lock`.
final class ReplaceableSession: @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    private let delegate: URLSessionDelegate
    private let lock = NSLock()
    private var session: URLSession

    init(configuration: URLSessionConfiguration, delegate: URLSessionDelegate) {
        self.configuration = configuration
        self.delegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    var current: URLSession {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    /// Requests already running finish on the old session; signing out (`cancelsRunningTasks`)
    /// stops them too, so nothing keeps talking as the previous user.
    func replace(cancelsRunningTasks: Bool) {
        lock.lock()
        let old = session
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        lock.unlock()
        if cancelsRunningTasks {
            old.invalidateAndCancel()
        } else {
            old.finishTasksAndInvalidate()
        }
    }
}
