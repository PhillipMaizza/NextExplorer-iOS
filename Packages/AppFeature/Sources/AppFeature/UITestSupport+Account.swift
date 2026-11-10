#if DEBUG
    import CoreModels
    import FilesClient
    import Foundation

    extension UITestSupport {
        /// The account password the mocked account routes accept. Mirrored by `Fixture.accountPassword`.
        static let accountPassword = "hunter2"
        /// What the mocked routes answer a wrong code or password with, as the server does.
        static let wrongCodeMessage = "Invalid code"
        static let wrongPasswordMessage = "That password is not right."
        static let twoFactorSecret = "JBSWY3DPEHPK3PXP"
        static let recoveryCodes = ["2HSMP-G9ZSJ", "K3QWE-7RTYU", "ABCDE-FGHJK", "MNPQR-STUVW"]

        /// The signed in account's second factor, kept in memory for one app launch so a UI test can
        /// turn it on and then see it on.
        final class MockAccountStore: @unchecked Sendable {
            private let lock = NSLock()
            private var isTwoFactorEnabled = false

            private func locked<T>(_ body: () -> T) -> T {
                lock.lock(); defer { lock.unlock() }
                return body()
            }

            var twoFactorStatus: TwoFactorStatus {
                locked { TwoFactorStatus(isEnabled: isTwoFactorEnabled, recoveryCodesLeft: isTwoFactorEnabled ? UITestSupport.recoveryCodes.count : 0) }
            }

            func setTwoFactor(enabled: Bool) {
                locked { isTwoFactorEnabled = enabled }
            }
        }

        static func installAccountMocks(into client: inout FilesClient) {
            let account = MockAccountStore()
            let wrongCode = FilesClientError.serverMessage(statusCode: 401, message: wrongCodeMessage)
            let wrongPassword = FilesClientError.serverMessage(statusCode: 401, message: wrongPasswordMessage)

            client.fetchTwoFactorStatus = { _ in account.twoFactorStatus }
            client.beginTwoFactorSetup = { _ in
                TwoFactorSetup(secret: twoFactorSecret, uri: "otpauth://totp/NextExplorer:phillip?secret=\(twoFactorSecret)&issuer=NextExplorer")
            }
            client.confirmTwoFactorSetup = { _, code in
                guard code == validCode else { throw wrongCode }
                account.setTwoFactor(enabled: true)
                return recoveryCodes
            }
            client.replaceRecoveryCodes = { _, password in
                guard password == accountPassword else { throw wrongPassword }
                return recoveryCodes
            }
            client.disableTwoFactor = { _, password in
                guard password == accountPassword else { throw wrongPassword }
                account.setTwoFactor(enabled: false)
            }
        }
    }
#endif
