import Dependencies
import Foundation
import Network

/// Proactive reachability, so the app can react to the connection coming back (auto refresh the
/// visible tab, drop the "saved copy" banner) instead of only discovering it through the next
/// failed request. `events()` yields the new online state on every change; `isOnline()` is the
/// current snapshot. Backed by a single process wide `NWPathMonitor`.
public struct ConnectivityClient: Sendable {
    public var isOnline: @Sendable () -> Bool
    /// A stream that yields `true`/`false` each time reachability flips. Multiple subscribers are
    /// supported; each gets the current value immediately, then every subsequent change.
    public var events: @Sendable () -> AsyncStream<Bool>

    public init(isOnline: @escaping @Sendable () -> Bool, events: @escaping @Sendable () -> AsyncStream<Bool>) {
        self.isOnline = isOnline
        self.events = events
    }
}

extension ConnectivityClient: DependencyKey {
    public static let liveValue: ConnectivityClient = {
        let monitor = Monitor()
        return ConnectivityClient(isOnline: { monitor.currentIsOnline }, events: { monitor.stream() })
    }()

    /// Always online, no events — matches the existing "assume connected" behavior in tests.
    public static let testValue = ConnectivityClient(
        isOnline: { true },
        events: { AsyncStream { _ in } }
    )

    public static let previewValue = ConnectivityClient.testValue

    private final class Monitor: @unchecked Sendable {
        private let lock = NSLock()
        private let monitor = NWPathMonitor()
        private let queue = DispatchQueue(label: "com.nextexplorer.connectivity")
        private var isOnline = true
        private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

        init() {
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                let online = path.status == .satisfied
                self.lock.lock()
                let changed = online != self.isOnline
                self.isOnline = online
                let sinks = changed ? Array(self.continuations.values) : []
                self.lock.unlock()
                for sink in sinks { sink.yield(online) }
            }
            monitor.start(queue: queue)
        }

        var currentIsOnline: Bool {
            lock.lock(); defer { lock.unlock() }
            return isOnline
        }

        func stream() -> AsyncStream<Bool> {
            AsyncStream { continuation in
                let id = UUID()
                lock.lock()
                let current = isOnline
                continuations[id] = continuation
                lock.unlock()
                continuation.yield(current)
                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    self.lock.lock()
                    self.continuations[id] = nil
                    self.lock.unlock()
                }
            }
        }
    }
}

public extension DependencyValues {
    var connectivity: ConnectivityClient {
        get { self[ConnectivityClient.self] }
        set { self[ConnectivityClient.self] = newValue }
    }
}
