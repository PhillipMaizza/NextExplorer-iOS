import Foundation

/// Ends the extension's request once: the system rejects a second `completeRequest` or
/// `cancelRequest`, so whichever close comes first wins and later ones are ignored.
@MainActor
public final class ExtensionCloser {
    private let complete: @MainActor () -> Void
    private let cancel: @MainActor () -> Void
    public private(set) var isClosed = false

    public init(complete: @escaping @MainActor () -> Void, cancel: @escaping @MainActor () -> Void) {
        self.complete = complete
        self.cancel = cancel
    }

    public func close(completed: Bool) {
        guard !isClosed else { return }
        isClosed = true
        if completed {
            complete()
        } else {
            cancel()
        }
    }
}
