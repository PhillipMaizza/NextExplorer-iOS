@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("TwoFactor")
struct TwoFactorTests {
    @Test("decodes an enabled status, whose keys are enabled and pending on the wire")
    func decodesEnabled() throws {
        let status = try CoreModelsFixture.twoFactorEnabled.decode(TwoFactorStatus.self)
        #expect(status == TwoFactorStatus(
            isEnabled: true,
            isPending: false,
            confirmedAt: "2026-11-10T07:00:00.000Z",
            recoveryCodesLeft: 8
        ))
    }

    @Test("decodes a status that was never confirmed, with a null date")
    func decodesPending() throws {
        let status = try CoreModelsFixture.twoFactorPendingNeverConfirmed.decode(TwoFactorStatus.self)
        #expect(!status.isEnabled)
        #expect(status.isPending)
        #expect(status.confirmedAt == nil)
    }

    @Test("edge case: a status without a date key decodes")
    func decodesWithoutDate() throws {
        #expect(try CoreModelsFixture.twoFactorWithoutConfirmedDate.decode(TwoFactorStatus.self).confirmedAt == nil)
    }

    @Test("edge case: a status missing a required key does not decode")
    func missingKeyFails() throws {
        let json = try CoreModelsFixture.twoFactorMissingRequiredKeys.data()
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(TwoFactorStatus.self, from: json) }
    }

    @Test("decodes the setup the server draws")
    func decodesSetup() throws {
        let setup = try CoreModelsFixture.twoFactorSetup.decode(TwoFactorSetup.self)
        #expect(setup.secret == TestAccount.totpSecret)
        #expect(setup.uri.hasPrefix("otpauth://"))
    }
}
