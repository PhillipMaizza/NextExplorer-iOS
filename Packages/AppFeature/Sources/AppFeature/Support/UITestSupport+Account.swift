#if DEBUG
    import CoreModels
    import FilesClient
    import Foundation

    extension UITestSupport {
        /// The account password the mocked two factor and token routes accept. Mirrored by
        /// `Fixture.accountPassword`.
        static let accountPassword = "hunter2"
        /// The message the mocked routes answer a wrong code or password with, as the server does.
        static let wrongCodeMessage = "Invalid code"
        static let wrongPasswordMessage = "That password is not right."
        static let twoFactorSecret = "JBSWY3DPEHPK3PXP"
        static let recoveryCodes = ["2HSMP-G9ZSJ", "K3QWE-7RTYU", "ABCDE-FGHJK", "MNPQR-STUVW"]

        /// The signed in account's second factor and API tokens, kept in memory for one app launch so
        /// a UI test can turn two factor on and see it on, or make a token and see it listed.
        final class MockAccountStore: @unchecked Sendable {
            private let lock = NSLock()
            private var isTwoFactorEnabled = false
            private var tokens: [APIToken] = []
            private var nextTokenNumber = 1

            private func locked<T>(_ body: () -> T) -> T {
                lock.lock(); defer { lock.unlock() }
                return body()
            }

            var twoFactorStatus: TwoFactorStatus {
                locked { TwoFactorStatus(
                    isEnabled: isTwoFactorEnabled,
                    recoveryCodesLeft: isTwoFactorEnabled ? UITestSupport.recoveryCodes.count : 0
                ) }
            }

            func setTwoFactor(enabled: Bool) {
                locked { isTwoFactorEnabled = enabled }
            }

            func currentTokens() -> [APIToken] {
                locked { tokens }
            }

            func addToken(name: String, scope: APIToken.Scope, expiresInDays: Int?) -> IssuedAPIToken {
                locked {
                    let token = APIToken(
                        id: "token-\(nextTokenNumber)", name: name, scope: scope,
                        createdAt: "2026-11-10T07:00:00.000Z",
                        expiresAt: expiresInDays == nil ? nil : "2027-02-01T00:00:00.000Z"
                    )
                    nextTokenNumber += 1
                    tokens.append(token)
                    return IssuedAPIToken(token: token, secret: "nxt_uitest.\(token.id)")
                }
            }

            func renameToken(id: String, to name: String) -> APIToken? {
                locked {
                    guard let index = tokens.firstIndex(where: { $0.id == id }) else { return nil }
                    let old = tokens[index]
                    tokens[index] = APIToken(
                        id: old.id,
                        name: name,
                        scope: old.scope,
                        createdAt: old.createdAt,
                        expiresAt: old.expiresAt
                    )
                    return tokens[index]
                }
            }

            func revokeToken(id: String) {
                locked { tokens.removeAll { $0.id == id } }
            }
        }

        static func installAccountMocks(into client: inout FilesClient) {
            let account = MockAccountStore()
            let wrongCode = FilesClientError.serverMessage(statusCode: 401, message: wrongCodeMessage)
            let wrongPassword = FilesClientError.serverMessage(statusCode: 401, message: wrongPasswordMessage)

            client.fetchTwoFactorStatus = { _ in account.twoFactorStatus }
            client.beginTwoFactorSetup = { _ in
                TwoFactorSetup(
                    secret: twoFactorSecret,
                    uri: "otpauth://totp/NextExplorer:phillip?secret=\(twoFactorSecret)&issuer=NextExplorer"
                )
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

            client.fetchAPITokens = { _ in account.currentTokens() }
            client.createAPIToken = { _, name, scope, expiresInDays, password in
                guard password == accountPassword else { throw wrongPassword }
                return account.addToken(name: name, scope: scope, expiresInDays: expiresInDays)
            }
            client.renameAPIToken = { _, id, name in
                guard let token = account.renameToken(id: id, to: name) else {
                    throw FilesClientError.serverMessage(
                        statusCode: 404,
                        message: "There is no such token on this account."
                    )
                }
                return token
            }
            client.revokeAPIToken = { _, id in account.revokeToken(id: id) }
        }
    }
#endif
