import Dependencies
import Testing

/// Gives every test case its own dependency values, and with them its own `@Shared(.inMemory)` storage.
///
/// `@Suite(.dependencies)` from DependenciesTestSupport resets the values once, at the outermost scope,
/// so the tests of one suite still share them and race each other on process wide in memory state while
/// Swift Testing runs them in parallel. This trait scopes each test case instead.
public struct IsolatedDependenciesTrait: SuiteTrait, TestTrait, TestScoping {
    public var isRecursive: Bool { true }

    public init() {}

    public func provideScope(
        for _: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        guard testCase != nil else {
            try await function()
            return
        }
        try await withDependencies {
            $0 = DependencyValues()
        } operation: {
            try await function()
        }
    }
}

public extension Trait where Self == IsolatedDependenciesTrait {
    static var isolatedDependencies: Self { Self() }
}
