import Foundation
import TestUtils

extension CoreModelsFixture {
    /// Decodes a fixture whose dates are ISO 8601 text, as the server sends them.
    func decodeISO<Value: Decodable>(_ type: Value.Type = Value.self) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decode(type, using: decoder)
    }
}
