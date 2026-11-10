@testable import CoreModels
import Foundation
import Testing

@Suite("TwoFactor")
struct TwoFactorTests {
    @Test("decodes an enabled status, whose keys are enabled and pending on the wire")
    func decodesEnabled() throws {
        let json = Data(#"{"enabled":true,"pending":false,"confirmedAt":"2026-11-10T07:00:00.000Z","recoveryCodesLeft":8}"#.utf8)
        let status = try JSONDecoder().decode(TwoFactorStatus.self, from: json)
        #expect(status == TwoFactorStatus(isEnabled: true, isPending: false, confirmedAt: "2026-11-10T07:00:00.000Z", recoveryCodesLeft: 8))
    }

    @Test("decodes a status that was never confirmed, with a null date")
    func decodesPending() throws {
        let json = Data(#"{"enabled":false,"pending":true,"confirmedAt":null,"recoveryCodesLeft":0}"#.utf8)
        let status = try JSONDecoder().decode(TwoFactorStatus.self, from: json)
        #expect(!status.isEnabled)
        #expect(status.isPending)
        #expect(status.confirmedAt == nil)
    }

    @Test("edge case: a status without a date key decodes")
    func decodesWithoutDate() throws {
        let json = Data(#"{"enabled":false,"pending":false,"recoveryCodesLeft":0}"#.utf8)
        #expect(try JSONDecoder().decode(TwoFactorStatus.self, from: json).confirmedAt == nil)
    }

    @Test("edge case: a status missing a required key does not decode")
    func missingKeyFails() {
        let json = Data(#"{"enabled":true}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(TwoFactorStatus.self, from: json) }
    }

    @Test("decodes the setup the server draws")
    func decodesSetup() throws {
        let json = Data(#"{"secret":"JBSWY3DPEHPK3PXP","uri":"otpauth://totp/x?secret=JBSWY3DPEHPK3PXP"}"#.utf8)
        let setup = try JSONDecoder().decode(TwoFactorSetup.self, from: json)
        #expect(setup.secret == "JBSWY3DPEHPK3PXP")
        #expect(setup.uri.hasPrefix("otpauth://"))
    }
}
