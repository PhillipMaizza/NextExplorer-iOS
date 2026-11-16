import Foundation

/// A destructive action that asks first: nothing happening, its confirmation on screen, or the
/// confirmed work running. One value in place of an `isConfirming` flag beside an `isRunning` one,
/// so the confirmation can never show while the work it asks about is already running.
public enum ConfirmPhase: Equatable, Sendable {
    case idle
    case confirming
    case running

    /// Whether the confirmation is on screen.
    public var isConfirming: Bool {
        self == .confirming
    }

    /// Whether the confirmed work is running; its button shows a spinner and stays disabled.
    public var isRunning: Bool {
        self == .running
    }

    /// The phase after the user asks for the action: a running one is never asked about again.
    public mutating func ask() {
        if self == .idle {
            self = .confirming
        }
    }

    /// The phase after the confirmation is dismissed without going ahead.
    public mutating func cancel() {
        if self == .confirming {
            self = .idle
        }
    }
}
