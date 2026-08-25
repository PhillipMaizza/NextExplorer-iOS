import DependenciesMacros
import Foundation

@DependencyClient
public struct KeychainClient: Sendable {
    public var save: @Sendable (_ key: String, _ data: Data) throws -> Void
    public var load: @Sendable (_ key: String) throws -> Data?
    public var delete: @Sendable (_ key: String) throws -> Void
}
