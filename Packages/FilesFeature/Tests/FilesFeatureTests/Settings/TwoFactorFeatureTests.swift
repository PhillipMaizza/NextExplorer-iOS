import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct TwoFactorFeatureTests {
    private typealias Store = TestStoreOf<TwoFactorFeature>

    private let serverURL = SettingsTestSupport.serverURL
    private let setup = TwoFactorSetup(
        secret: "JBSWY3DPEHPK3PXP",
        uri: "otpauth://totp/NextExplorer:alice?secret=JBSWY3DPEHPK3PXP"
    )
    private let codes = ["2HSMP-G9ZSJ", "K3QWE-7RTYU"]
    private let wrongCode = FilesClientError.serverMessage(statusCode: 401, message: "Invalid code")
    private let wrongPassword = FilesClientError.serverMessage(statusCode: 401, message: "Incorrect password")
    private let confirmCalls = LockIsolated<[String]>([])
    private let replaceCalls = LockIsolated<[String]>([])
    private let disableCalls = LockIsolated<[String]>([])
    private let setupCalls = LockIsolated(0)

    private func makeStore(
        phase: TwoFactorFeature.Phase = .loading,
        status: @escaping @Sendable () async throws -> TwoFactorStatus = { throw FilesClientError.offline },
        beginSetup: @escaping @Sendable () async throws -> TwoFactorSetup = { throw FilesClientError.offline },
        confirm: @escaping @Sendable () async throws -> [String] = { throw FilesClientError.offline },
        replace: @escaping @Sendable () async throws -> [String] = { throw FilesClientError.offline },
        disable: @escaping @Sendable () async throws -> Void = { throw FilesClientError.offline },
        initial: (inout TwoFactorFeature.State) -> Void = { _ in }
    ) -> Store {
        var state = TwoFactorFeature.State(serverURL: serverURL, phase: phase)
        initial(&state)
        let confirmCalls = confirmCalls
        let replaceCalls = replaceCalls
        let disableCalls = disableCalls
        let setupCalls = setupCalls
        return TestStore(initialState: state) {
            TwoFactorFeature()
        } withDependencies: {
            $0.filesClient.fetchTwoFactorStatus = { _ in try await status() }
            $0.filesClient.beginTwoFactorSetup = { _ in
                setupCalls.withValue { $0 += 1 }
                return try await beginSetup()
            }
            $0.filesClient.confirmTwoFactorSetup = { _, code in
                confirmCalls.withValue { $0.append(code) }
                return try await confirm()
            }
            $0.filesClient.replaceRecoveryCodes = { _, password in
                replaceCalls.withValue { $0.append(password) }
                return try await replace()
            }
            $0.filesClient.disableTwoFactor = { _, password in
                disableCalls.withValue { $0.append(password) }
                try await disable()
            }
        }
    }

    // MARK: Loading

    @Test
    func anAccountWithoutTwoFactorLoadsAsOff() async {
        let store = makeStore(status: { TwoFactorStatus(isEnabled: false) })

        await store.send(.task)
        await store.receive(\.statusResponse.success) { $0.phase = .off }
    }

    @Test
    func anAccountWithTwoFactorLoadsAsOnWithItsRecoveryCodesLeft() async {
        let store =
            makeStore(status: { TwoFactorStatus(isEnabled: true, confirmedAt: "2026-11-10", recoveryCodesLeft: 7) })

        await store.send(.task)
        await store.receive(\.statusResponse.success) { $0.phase = .on(recoveryCodesLeft: 7) }
    }

    @Test
    func aPendingSetupThatWasNeverConfirmedIsStillOff() async {
        let store = makeStore(status: { TwoFactorStatus(isEnabled: false, isPending: true) })

        await store.send(.task)
        await store.receive(\.statusResponse.success) { $0.phase = .off }
    }

    @Test
    func aFailedLoadShowsTheMessageAndRetryLoadsAgain() async {
        let attempts = LockIsolated(0)
        let store = makeStore(status: {
            if attempts.withValue({ $0 += 1; return $0 }) == 1 {
                throw FilesClientError.rateLimited
            }
            return TwoFactorStatus(isEnabled: true, recoveryCodesLeft: 3)
        })

        await store.send(.task)
        await store.receive(\.statusResponse.failure) { $0.phase = .failed(L10n.Error.rateLimited) }
        await store.send(.retryTapped) { $0.phase = .loading }
        await store.receive(\.statusResponse.success) { $0.phase = .on(recoveryCodesLeft: 3) }
        #expect(attempts.value == 2)
    }

    // MARK: Turning on

    @Test
    func turningOnShowsTheSecretAndAsksForACode() async {
        let store = makeStore(phase: .off, beginSetup: { [setup] in setup })

        await store.send(.turnOnTapped) { $0.isWorking = true }
        await store.receive(\.setupResponse.success) {
            $0.isWorking = false
            $0.phase = .enrolling(setup)
        }
    }

    @Test
    func turningOnWithoutAPasswordSessionShowsTheServersMessageAndStaysOff() async {
        let store = makeStore(phase: .off, beginSetup: {
            throw FilesClientError.serverMessage(statusCode: 403, message: "Sign in with your password to set this up")
        })

        await store.send(.turnOnTapped) { $0.isWorking = true }
        await store.receive(\.setupResponse.failure) {
            $0.isWorking = false
            $0.errorMessage = "Sign in with your password to set this up"
        }
        #expect(store.state.phase == .off)
    }

    @Test
    func turnOnIsIgnoredWhenAlreadyOn() async {
        let store = makeStore(phase: .on(recoveryCodesLeft: 1), beginSetup: { [setup] in setup })

        await store.send(.turnOnTapped)
        #expect(setupCalls.value == 0)
    }

    @Test
    func turnOnIsIgnoredWhileWorking() async {
        let store = makeStore(phase: .off, beginSetup: { [setup] in setup }, initial: { $0.isWorking = true })

        await store.send(.turnOnTapped)
        #expect(setupCalls.value == 0)
    }

    // MARK: The code

    struct CodeCase: Sendable {
        let typed: String
        let kept: String
    }

    @Test(
        "The code keeps only ASCII digits and at most six",
        arguments: [
            CodeCase(typed: "12 34-5", kept: "12345"),
            CodeCase(typed: "12a3b4c5", kept: "12345"),
            CodeCase(typed: "abc", kept: ""),
            CodeCase(typed: "١٢٣٤٥٦", kept: ""),
            CodeCase(typed: "", kept: ""),
        ]
    )
    func theCodeKeepsOnlyDigits(_ testCase: CodeCase) async {
        let store = makeStore(phase: .enrolling(setup), initial: { $0.code = "99" })

        await store.send(.codeChanged(testCase.typed)) { $0.code = testCase.kept }
        #expect(confirmCalls.value.isEmpty)
    }

    @Test
    func fiveDigitsDoNotConfirmEvenWhenTheButtonIsTapped() async {
        let store = makeStore(phase: .enrolling(setup))

        await store.send(.codeChanged("12345")) { $0.code = "12345" }
        await store.send(.confirmTapped)
        #expect(confirmCalls.value.isEmpty)
    }

    @Test
    func theSixthDigitConfirmsAndSendsTheCode() async {
        let store = makeStore(phase: .enrolling(setup), confirm: { [codes] in codes })

        await store.send(.codeChanged(TestAccount.totpCode)) { $0.code = TestAccount.totpCode }
        await store.receive(\.confirmTapped) { $0.isWorking = true }
        await store.receive(\.confirmResponse.success) {
            $0.isWorking = false
            $0.code = ""
            $0.phase = .showingRecoveryCodes(codes)
        }
        #expect(confirmCalls.value == [TestAccount.totpCode])
    }

    @Test
    func pastingMoreThanSixDigitsConfirmsTheFirstSix() async {
        let store = makeStore(phase: .enrolling(setup), confirm: { [codes] in codes })

        await store.send(.codeChanged("1234567890")) { $0.code = TestAccount.totpCode }
        await store.receive(\.confirmTapped) { $0.isWorking = true }
        await store.receive(\.confirmResponse.success) {
            $0.isWorking = false
            $0.code = ""
            $0.phase = .showingRecoveryCodes(codes)
        }
        #expect(confirmCalls.value == [TestAccount.totpCode])
    }

    @Test
    func aWrongCodeIsClearedSoItCanBeTypedAgain() async {
        let failure = wrongCode
        let store = makeStore(phase: .enrolling(setup), confirm: { throw failure })

        await store.send(.codeChanged("111111")) { $0.code = "111111" }
        await store.receive(\.confirmTapped) { $0.isWorking = true }
        await store.receive(\.confirmResponse.failure) {
            $0.isWorking = false
            $0.code = ""
            $0.errorMessage = "Invalid code"
        }
        #expect(store.state.phase == .enrolling(setup))
    }

    @Test
    func aDroppedConnectionKeepsTheTypedCode() async {
        let store = makeStore(phase: .enrolling(setup), confirm: { throw FilesClientError.rateLimited })

        await store.send(.codeChanged("111111")) { $0.code = "111111" }
        await store.receive(\.confirmTapped) { $0.isWorking = true }
        await store.receive(\.confirmResponse.failure) {
            $0.isWorking = false
            $0.errorMessage = L10n.Error.rateLimited
        }
        #expect(store.state.code == "111111")
    }

    @Test
    func aCodeTypedWhileAConfirmationIsInFlightIsNotSentTwice() async {
        let store = makeStore(phase: .enrolling(setup), confirm: { [codes] in codes }, initial: { $0.isWorking = true })

        await store.send(.codeChanged(TestAccount.totpCode)) { $0.code = TestAccount.totpCode }
        await store.send(.confirmTapped)
        #expect(confirmCalls.value.isEmpty)
    }

    @Test
    func theCodeFieldDoesNothingOutsideSetup() async {
        let store = makeStore(phase: .off, confirm: { [codes] in codes })

        await store.send(.codeChanged(TestAccount.totpCode)) { $0.code = TestAccount.totpCode }
        #expect(confirmCalls.value.isEmpty)
    }

    @Test
    func cancellingSetupGoesBackToOffAndDropsTheCode() async {
        let store = makeStore(phase: .enrolling(setup), initial: {
            $0.code = "123"
            $0.errorMessage = "x"
        })

        await store.send(.cancelSetupTapped) {
            $0.phase = .off
            $0.code = ""
            $0.errorMessage = nil
        }
    }

    @Test
    func cancellingSetupWhileAConfirmationIsInFlightDropsItsAnswer() async {
        let gate = AsyncGate()
        let store = makeStore(phase: .enrolling(setup), confirm: { [codes] in
            try await gate.wait()
            return codes
        })

        await store.send(.codeChanged(TestAccount.totpCode)) { $0.code = TestAccount.totpCode }
        await store.receive(\.confirmTapped) { $0.isWorking = true }
        await store.send(.cancelSetupTapped) {
            $0.phase = .off
            $0.code = ""
            $0.isWorking = false
        }
        await store.finish()
        #expect(confirmCalls.value == [TestAccount.totpCode])
    }

    // MARK: Recovery codes

    @Test
    func doneAfterTheCodesAreShownLandsOnOnWithTheirCount() async {
        let store = makeStore(phase: .showingRecoveryCodes(codes))

        await store.send(.recoveryCodesDoneTapped) { $0.phase = .on(recoveryCodesLeft: 2) }
    }

    @Test
    func doneIsIgnoredWhenNoCodesAreShown() async {
        let store = makeStore(phase: .off)

        await store.send(.recoveryCodesDoneTapped)
    }

    // MARK: Password prompt

    @Test
    func newRecoveryCodesAskForThePasswordFirstAndNeedOneToConfirm() async {
        let store = makeStore(phase: .on(recoveryCodesLeft: 1), replace: { [codes] in codes })

        await store.send(.newRecoveryCodesTapped) { $0.passwordPrompt = .init(action: .newRecoveryCodes) }
        #expect(!store.state.isPasswordPromptConfirmEnabled)
        await store.send(.passwordPromptConfirmed)
        #expect(replaceCalls.value.isEmpty)
    }

    @Test
    func newRecoveryCodesSendThePasswordAndShowTheNewCodes() async {
        let store = makeStore(phase: .on(recoveryCodesLeft: 1), replace: { [codes] in codes })

        await store.send(.newRecoveryCodesTapped) { $0.passwordPrompt = .init(action: .newRecoveryCodes) }
        await store.send(.passwordChanged(TestAccount.password)) { $0.passwordPrompt?.password = TestAccount.password }
        await store.send(.passwordPromptConfirmed) { $0.isWorking = true }
        await store.receive(\.recoveryCodesResponse.success) {
            $0.isWorking = false
            $0.passwordPrompt = nil
            $0.phase = .showingRecoveryCodes(codes)
        }
        #expect(replaceCalls.value == [TestAccount.password])
        #expect(disableCalls.value.isEmpty)
    }

    @Test
    func aWrongPasswordKeepsThePromptOpenWithTheMessage() async {
        let failure = wrongPassword
        let store = makeStore(phase: .on(recoveryCodesLeft: 1), replace: { throw failure })

        await store.send(.newRecoveryCodesTapped) { $0.passwordPrompt = .init(action: .newRecoveryCodes) }
        await store
            .send(.passwordChanged(TestAccount.rejectedPassword)) {
                $0.passwordPrompt?.password = TestAccount.rejectedPassword
            }
        await store.send(.passwordPromptConfirmed) { $0.isWorking = true }
        await store.receive(\.recoveryCodesResponse.failure) {
            $0.isWorking = false
            $0.errorMessage = "Incorrect password"
        }
        #expect(store.state.passwordPrompt?.password == TestAccount.rejectedPassword)
        #expect(store.state.phase == .on(recoveryCodesLeft: 1))
    }

    @Test
    func turningOffSendsThePasswordAndLandsOnOff() async {
        let store = makeStore(phase: .on(recoveryCodesLeft: 4), disable: {})

        await store.send(.turnOffTapped) { $0.passwordPrompt = .init(action: .turnOff) }
        await store.send(.passwordChanged(TestAccount.password)) { $0.passwordPrompt?.password = TestAccount.password }
        await store.send(.passwordPromptConfirmed) { $0.isWorking = true }
        await store.receive(\.disableResponse.success) {
            $0.isWorking = false
            $0.passwordPrompt = nil
            $0.phase = .off
        }
        #expect(disableCalls.value == [TestAccount.password])
        #expect(replaceCalls.value.isEmpty)
    }

    @Test
    func aWrongPasswordWhenTurningOffLeavesItOn() async {
        let failure = wrongPassword
        let store = makeStore(phase: .on(recoveryCodesLeft: 4), disable: { throw failure })

        await store.send(.turnOffTapped) { $0.passwordPrompt = .init(action: .turnOff) }
        await store
            .send(.passwordChanged(TestAccount.rejectedPassword)) {
                $0.passwordPrompt?.password = TestAccount.rejectedPassword
            }
        await store.send(.passwordPromptConfirmed) { $0.isWorking = true }
        await store.receive(\.disableResponse.failure) {
            $0.isWorking = false
            $0.errorMessage = "Incorrect password"
        }
        #expect(store.state.phase == .on(recoveryCodesLeft: 4))
    }

    @Test
    func cancellingThePromptClearsItAndTheError() async {
        let store = makeStore(phase: .on(recoveryCodesLeft: 4), initial: {
            $0.passwordPrompt = .init(action: .turnOff)
            $0.errorMessage = "x"
        })

        await store.send(.passwordPromptCancelled) {
            $0.passwordPrompt = nil
            $0.errorMessage = nil
        }
    }

    @Test
    func cancellingThePromptWhileTurningOffDropsTheAnswer() async {
        let gate = AsyncGate()
        let store = makeStore(phase: .on(recoveryCodesLeft: 4), disable: { try await gate.wait() })

        await store.send(.turnOffTapped) { $0.passwordPrompt = .init(action: .turnOff) }
        await store.send(.passwordChanged(TestAccount.password)) { $0.passwordPrompt?.password = TestAccount.password }
        await store.send(.passwordPromptConfirmed) { $0.isWorking = true }
        await store.send(.passwordPromptCancelled) {
            $0.passwordPrompt = nil
            $0.isWorking = false
        }
        await store.finish()
        #expect(store.state.phase == .on(recoveryCodesLeft: 4))
    }

    @Test
    func thePromptCannotBeOpenedWhileOff() async {
        let store = makeStore(phase: .off)

        await store.send(.turnOffTapped)
        await store.send(.newRecoveryCodesTapped)
    }

    @Test
    func thePromptCannotBeOpenedWhileWorking() async {
        let store = makeStore(phase: .on(recoveryCodesLeft: 1), initial: { $0.isWorking = true })

        await store.send(.turnOffTapped)
        await store.send(.newRecoveryCodesTapped)
    }
}
