import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct TwoFactorFeatureTests {
    private let serverURL = URL(string: "https://cloud.example.com")!
    private let setup = TwoFactorSetup(secret: "JBSWY3DPEHPK3PXP", uri: "otpauth://totp/NextExplorer:alice?secret=JBSWY3DPEHPK3PXP")
    private let codes = ["2HSMP-G9ZSJ", "K3QWE-7RTYU"]
    private let wrongCode = FilesClientError.serverMessage(statusCode: 401, message: "Invalid code")
    private let wrongPassword = FilesClientError.serverMessage(statusCode: 401, message: "Incorrect password")

    private func makeStore(
        phase: TwoFactorFeature.Phase = .loading,
        configure: (inout DependencyValues) -> Void = { _ in },
        initial: (inout TwoFactorFeature.State) -> Void = { _ in }
    ) -> TestStoreOf<TwoFactorFeature> {
        var state = TwoFactorFeature.State(serverURL: serverURL, phase: phase)
        initial(&state)
        let store = TestStore(initialState: state) {
            TwoFactorFeature()
        } withDependencies: { configure(&$0) }
        store.timeout = .seconds(10)
        return store
    }

    // MARK: Loading

    @Test
    func anAccountWithoutTwoFactorLoadsAsOff() async {
        let store = makeStore { $0.filesClient.fetchTwoFactorStatus = { _ in TwoFactorStatus(isEnabled: false) } }

        await store.send(.task)
        await store.receive(\.statusResponse) { $0.phase = .off }
    }

    @Test
    func anAccountWithTwoFactorLoadsAsOnWithItsRecoveryCodesLeft() async {
        let store = makeStore { $0.filesClient.fetchTwoFactorStatus = { _ in TwoFactorStatus(isEnabled: true, confirmedAt: "2026-11-10", recoveryCodesLeft: 7) } }

        await store.send(.task)
        await store.receive(\.statusResponse) { $0.phase = .on(recoveryCodesLeft: 7) }
    }

    @Test
    func aPendingSetupThatWasNeverConfirmedIsStillOff() async {
        let store = makeStore { $0.filesClient.fetchTwoFactorStatus = { _ in TwoFactorStatus(isEnabled: false, isPending: true) } }

        await store.send(.task)
        await store.receive(\.statusResponse) { $0.phase = .off }
    }

    @Test
    func aFailedLoadShowsTheMessageAndRetryLoadsAgain() async {
        let attempts = LockIsolated(0)
        let store = makeStore {
            $0.filesClient.fetchTwoFactorStatus = { _ in
                if attempts.withValue({ $0 += 1; return $0 }) == 1 {
                    throw FilesClientError.rateLimited
                }
                return TwoFactorStatus(isEnabled: true, recoveryCodesLeft: 3)
            }
        }

        await store.send(.task)
        await store.receive(\.statusResponse) { $0.phase = .failed(FilesClientError.rateLimited.userMessage) }
        await store.send(.retryTapped) { $0.phase = .loading }
        await store.receive(\.statusResponse) { $0.phase = .on(recoveryCodesLeft: 3) }
    }

    // MARK: Turning on

    @Test
    func turningOnShowsTheSecretAndAsksForACode() async {
        let store = makeStore(phase: .off) { $0.filesClient.beginTwoFactorSetup = { _ in setup } }

        await store.send(.turnOnTapped) { $0.isWorking = true }
        await store.receive(\.setupResponse) {
            $0.isWorking = false
            $0.phase = .enrolling(setup)
        }
    }

    @Test
    func turningOnWithoutAPasswordSessionShowsTheServersMessageAndStaysOff() async {
        let refusal = FilesClientError.serverMessage(statusCode: 403, message: "Sign in with your password to set this up")
        let store = makeStore(phase: .off) { $0.filesClient.beginTwoFactorSetup = { _ in throw refusal } }

        await store.send(.turnOnTapped) { $0.isWorking = true }
        await store.receive(\.setupResponse) {
            $0.isWorking = false
            $0.errorMessage = refusal.userMessage
        }
        #expect(store.state.phase == .off)
    }

    @Test
    func turnOnIsIgnoredWhenAlreadyOnOrWorking() async {
        let store = makeStore(phase: .on(recoveryCodesLeft: 1)) { $0.filesClient.beginTwoFactorSetup = { _ in Issue.record("must not start"); return setup } }
        await store.send(.turnOnTapped)

        let working = makeStore(
            phase: .off,
            configure: { $0.filesClient.beginTwoFactorSetup = { _ in Issue.record("must not start twice"); return setup } },
            initial: { $0.isWorking = true }
        )
        await working.send(.turnOnTapped)
    }

    // MARK: The code

    @Test
    func theCodeKeepsOnlyDigitsAndAtMostSix() async {
        let store = makeStore(phase: .enrolling(setup)) { $0.filesClient.confirmTwoFactorSetup = { _, _ in [] } }
        store.exhaustivity = .off

        await store.send(.codeChanged("12 34-5")) { $0.code = "12345" }
        await store.send(.codeChanged("abc")) { $0.code = "" }
        await store.send(.codeChanged("١٢٣٤٥٦")) { $0.code = "" }
    }

    @Test
    func fiveDigitsDoNotConfirm() async {
        let store = makeStore(phase: .enrolling(setup)) { $0.filesClient.confirmTwoFactorSetup = { _, _ in Issue.record("too early"); return [] } }

        await store.send(.codeChanged("12345")) { $0.code = "12345" }
        await store.send(.confirmTapped)
    }

    @Test
    func theSixthDigitConfirmsAndSendsTheCode() async {
        let sent = LockIsolated<String?>(nil)
        let store = makeStore(phase: .enrolling(setup)) {
            $0.filesClient.confirmTwoFactorSetup = { _, code in
                sent.setValue(code)
                return codes
            }
        }

        await store.send(.codeChanged("123456")) { $0.code = "123456" }
        await store.receive(\.confirmTapped) { $0.isWorking = true }
        await store.receive(\.confirmResponse) {
            $0.isWorking = false
            $0.code = ""
            $0.phase = .showingRecoveryCodes(codes)
        }
        #expect(sent.value == "123456")
    }

    @Test
    func pastingMoreThanSixDigitsConfirmsTheFirstSix() async {
        let sent = LockIsolated<String?>(nil)
        let store = makeStore(phase: .enrolling(setup)) { $0.filesClient.confirmTwoFactorSetup = { _, code in sent.setValue(code); return codes } }
        store.exhaustivity = .off

        await store.send(.codeChanged("1234567890"))
        await store.receive(\.confirmResponse)
        #expect(sent.value == "123456")
    }

    @Test
    func aWrongCodeIsClearedSoItCanBeTypedAgain() async {
        let store = makeStore(phase: .enrolling(setup)) { $0.filesClient.confirmTwoFactorSetup = { _, _ in throw wrongCode } }

        await store.send(.codeChanged("111111")) { $0.code = "111111" }
        await store.receive(\.confirmTapped) { $0.isWorking = true }
        await store.receive(\.confirmResponse) {
            $0.isWorking = false
            $0.code = ""
            $0.errorMessage = wrongCode.userMessage
        }
        #expect(store.state.phase == .enrolling(setup))
    }

    @Test
    func aDroppedConnectionKeepsTheTypedCode() async {
        let store = makeStore(phase: .enrolling(setup)) { $0.filesClient.confirmTwoFactorSetup = { _, _ in throw FilesClientError.rateLimited } }

        await store.send(.codeChanged("111111")) { $0.code = "111111" }
        await store.receive(\.confirmTapped) { $0.isWorking = true }
        await store.receive(\.confirmResponse) {
            $0.isWorking = false
            $0.errorMessage = FilesClientError.rateLimited.userMessage
        }
        #expect(store.state.code == "111111")
    }

    @Test
    func aCodeTypedWhileAConfirmationIsInFlightIsNotSentTwice() async {
        let calls = LockIsolated(0)
        let store = makeStore(
            phase: .enrolling(setup),
            configure: { $0.filesClient.confirmTwoFactorSetup = { _, _ in calls.withValue { $0 += 1 }; return codes } },
            initial: { $0.isWorking = true }
        )
        store.exhaustivity = .off

        await store.send(.codeChanged("123456"))
        await store.send(.confirmTapped)
        #expect(calls.value == 0)
    }

    @Test
    func theCodeFieldDoesNothingOutsideSetup() async {
        let store = makeStore(phase: .off) { $0.filesClient.confirmTwoFactorSetup = { _, _ in Issue.record("no setup"); return [] } }

        await store.send(.codeChanged("123456")) { $0.code = "123456" }
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

    // MARK: Recovery codes

    @Test
    func doneAfterTheCodesAreShownLandsOnOnWithTheirCount() async {
        let store = makeStore(phase: .showingRecoveryCodes(codes))

        await store.send(.recoveryCodesDoneTapped) { $0.phase = .on(recoveryCodesLeft: 2) }
    }

    @Test
    func doneIsIgnoredWhenNoCodesAreShown() async {
        await makeStore(phase: .off).send(.recoveryCodesDoneTapped)
    }

    // MARK: Password prompt

    @Test
    func newRecoveryCodesAskForThePasswordFirst() async {
        let store = makeStore(phase: .on(recoveryCodesLeft: 1))

        await store.send(.newRecoveryCodesTapped) { $0.passwordPrompt = .init(action: .newRecoveryCodes) }
        #expect(!store.state.isPasswordPromptConfirmEnabled)
        await store.send(.passwordPromptConfirmed)
    }

    @Test
    func newRecoveryCodesSendThePasswordAndShowTheNewCodes() async {
        let sent = LockIsolated<String?>(nil)
        let store = makeStore(phase: .on(recoveryCodesLeft: 1)) {
            $0.filesClient.replaceRecoveryCodes = { _, password in sent.setValue(password); return codes }
        }

        await store.send(.newRecoveryCodesTapped) { $0.passwordPrompt = .init(action: .newRecoveryCodes) }
        await store.send(.passwordChanged("hunter2")) { $0.passwordPrompt?.password = "hunter2" }
        await store.send(.passwordPromptConfirmed) { $0.isWorking = true }
        await store.receive(\.recoveryCodesResponse) {
            $0.isWorking = false
            $0.passwordPrompt = nil
            $0.phase = .showingRecoveryCodes(codes)
        }
        #expect(sent.value == "hunter2")
    }

    @Test
    func aWrongPasswordKeepsThePromptOpenWithTheMessage() async {
        let store = makeStore(phase: .on(recoveryCodesLeft: 1)) { $0.filesClient.replaceRecoveryCodes = { _, _ in throw wrongPassword } }

        await store.send(.newRecoveryCodesTapped) { $0.passwordPrompt = .init(action: .newRecoveryCodes) }
        await store.send(.passwordChanged("nope")) { $0.passwordPrompt?.password = "nope" }
        await store.send(.passwordPromptConfirmed) { $0.isWorking = true }
        await store.receive(\.recoveryCodesResponse) {
            $0.isWorking = false
            $0.errorMessage = wrongPassword.userMessage
        }
        #expect(store.state.passwordPrompt?.password == "nope")
        #expect(store.state.phase == .on(recoveryCodesLeft: 1))
    }

    @Test
    func turningOffSendsThePasswordAndLandsOnOff() async {
        let sent = LockIsolated<String?>(nil)
        let store = makeStore(phase: .on(recoveryCodesLeft: 4)) { $0.filesClient.disableTwoFactor = { _, password in sent.setValue(password) } }

        await store.send(.turnOffTapped) { $0.passwordPrompt = .init(action: .turnOff) }
        await store.send(.passwordChanged("hunter2")) { $0.passwordPrompt?.password = "hunter2" }
        await store.send(.passwordPromptConfirmed) { $0.isWorking = true }
        await store.receive(\.disableResponse) {
            $0.isWorking = false
            $0.passwordPrompt = nil
            $0.phase = .off
        }
        #expect(sent.value == "hunter2")
    }

    @Test
    func aWrongPasswordWhenTurningOffLeavesItOn() async {
        let store = makeStore(phase: .on(recoveryCodesLeft: 4)) { $0.filesClient.disableTwoFactor = { _, _ in throw wrongPassword } }

        await store.send(.turnOffTapped) { $0.passwordPrompt = .init(action: .turnOff) }
        await store.send(.passwordChanged("nope")) { $0.passwordPrompt?.password = "nope" }
        await store.send(.passwordPromptConfirmed) { $0.isWorking = true }
        await store.receive(\.disableResponse) {
            $0.isWorking = false
            $0.errorMessage = wrongPassword.userMessage
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
    func thePromptCannotBeOpenedWhileOffOrWorking() async {
        await makeStore(phase: .off).send(.turnOffTapped)
        await makeStore(phase: .off).send(.newRecoveryCodesTapped)

        let working = makeStore(phase: .on(recoveryCodesLeft: 1), initial: { $0.isWorking = true })
        await working.send(.turnOffTapped)
    }
}
