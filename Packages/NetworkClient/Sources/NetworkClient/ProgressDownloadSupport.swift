import Foundation

/// Shares a started download task with the cancellation handler wrapping it, so cancelling the Swift
/// task cancels the URLSession task. Handles the race where cancellation arrives before the task is
/// even created.
final class DownloadTaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var cancelled = false

    /// Stores the started task, or returns `false` if cancellation already arrived (the caller then
    /// cancels the task immediately instead of resuming it).
    func store(_ task: URLSessionDownloadTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        self.task = task
        return true
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        task?.cancel()
    }
}

/// Rate limits fractional progress so a fast transfer doesn't fire the callback thousands of times.
/// The KVO progress observation can be invoked from any thread, so the timestamp is lock guarded.
/// A completion (`fraction >= 1`) always passes through.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private let onProgress: @Sendable (Double) -> Void
    private let minInterval: TimeInterval
    private var lastEmit = 0.0

    init(minInterval: TimeInterval = 0.1, onProgress: @escaping @Sendable (Double) -> Void) {
        self.minInterval = minInterval
        self.onProgress = onProgress
    }

    func report(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        lock.lock()
        let now = CFAbsoluteTimeGetCurrent()
        let shouldEmit = clamped >= 1 || now - lastEmit >= minInterval
        if shouldEmit {
            lastEmit = now
        }
        lock.unlock()
        guard shouldEmit else { return }
        onProgress(clamped)
    }
}

/// Holds the KVO progress observation for the lifetime of a download and tears it down exactly once,
/// from whichever of the completion handler or cancellation runs first.
final class ProgressObservationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var observation: NSKeyValueObservation?

    func set(_ observation: NSKeyValueObservation) {
        lock.lock()
        defer { lock.unlock() }
        self.observation = observation
    }

    func invalidate() {
        lock.lock()
        let toInvalidate = observation
        observation = nil
        lock.unlock()
        toInvalidate?.invalidate()
    }
}
