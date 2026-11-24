import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The edit page's own flow: expiry presets, the change check behind Back and Save, the password
/// check, the discard confirm, and loading people for a Specific users share.
@Suite(.isolatedDependencies)
@MainActor
struct EditShareFlowTests {
    private enum Constants {
        static let day: TimeInterval = 86_400
        static let week: TimeInterval = 604_800
    }

    private let serverURL = TestHost.serverURL
    private let fixedNow = MockDate.date.addingTimeInterval(100_000_000)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func state(_ share: Share = .editFixture()) -> EditShareFeature.State {
        EditShareFeature.State(serverURL: serverURL, share: share, now: fixedNow)
    }

    @Test
    func anExpiredShareOpensOnCustomAWeekOutReadyToSave() {
        let state = state(.editFixture(expiresAt: fixedNow.addingTimeInterval(-Constants.day)))

        #expect(state.isExpired)
        #expect(state.expiryPreset == .custom)
        #expect(state.expiresAt == fixedNow.addingTimeInterval(Constants.week))
        #expect(state.hasChanges)
        #expect(state.daysLeft == 7)
    }

    @Test
    func aShareWithoutExpiryOpensOnNeverAndADatedOneOnCustom() {
        #expect(state().expiryPreset == .never)
        #expect(!state().isExpiryEnabled)

        let dated = state(.editFixture(expiresAt: fixedNow.addingTimeInterval(Constants.day * 3)))
        #expect(dated.expiryPreset == .custom)
        #expect(!dated.isExpired)
        #expect(!dated.hasChanges)
    }

    @Test
    func presetsCountFromNowAndPickingADateMeansCustom() async {
        let store = TestStore(initialState: state()) { EditShareFeature() } withDependencies: {
            $0.date = .constant(fixedNow)
            $0.calendar = utcCalendar
        }

        await store.send(.expiryPresetTapped(.day)) {
            $0.expiryPreset = .day
            $0.expiresAt = fixedNow.addingTimeInterval(Constants.day)
        }
        await store.send(.expiryPresetTapped(.month)) {
            $0.expiryPreset = .month
            $0.expiresAt = utcCalendar.date(byAdding: .month, value: 1, to: fixedNow) ?? fixedNow
        }
        await store.send(.expiryPresetTapped(.custom)) { $0.expiryPreset = .custom }
        let picked = fixedNow.addingTimeInterval(Constants.day * 40)
        await store.send(.expiryPresetTapped(.never)) { $0.expiryPreset = .never }
        await store.send(.expiresAtChanged(picked)) {
            $0.expiresAt = picked
            $0.expiryPreset = .custom
        }
        await store.send(.expiryEnabledChanged(false)) { $0.expiryPreset = .never }
    }

    @Test
    func theLabelOpensFilledWithTheNameAndAnUntouchedNameStaysUnlabeled() {
        var unlabeled = state(.editFixture(label: nil))
        #expect(unlabeled.label == "Report")
        #expect(unlabeled.savedLabel == nil)
        #expect(!unlabeled.hasChanges)

        unlabeled.label = "  Quarterly  "
        #expect(unlabeled.savedLabel == "Quarterly")
        #expect(unlabeled.isSaveEnabled)

        unlabeled.label = "   "
        #expect(unlabeled.hasChanges)
        #expect(!unlabeled.isSaveEnabled)

        #expect(state(.editFixture(label: "Bills")).label == "Bills")
    }

    @Test
    func theChangeCheckFollowsTheDraftBackToTheSavedShare() {
        var draft = state(.editFixture(target: .users, permittedUserIds: ["u2"]))
        #expect(!draft.hasChanges)
        #expect(!draft.isSaveEnabled)

        draft.label = "Report "
        #expect(!draft.hasChanges)
        draft.label = "Bills"
        #expect(draft.hasChanges)
        draft.label = "Report"

        draft.selectedUserIDs = ["u2", "u3"]
        #expect(draft.hasChanges)
        draft.selectedUserIDs = []
        #expect(draft.hasChanges)
        #expect(!draft.isSaveEnabled)
        draft.selectedUserIDs = ["u2"]

        draft.newPassword = TestAccount.password
        #expect(draft.hasChanges)
        #expect(draft.isLeavingGuarded)
    }

    @Test
    func turningOnAPasswordWithoutTypingOneStopsSave() async {
        var initial = state()
        initial.isPasswordEnabled = true
        let store = TestStore(initialState: initial) { EditShareFeature() } withDependencies: {
            $0.date = .constant(fixedNow)
        }

        #expect(store.state.isPasswordMissing)
        await store.send(.saveTapped) { $0.fieldError = .passwordRequired }
        await store.send(.newPasswordChanged(TestAccount.password)) {
            $0.newPassword = TestAccount.password
            $0.fieldError = nil
        }
        #expect(!store.state.isPasswordMissing)
    }

    @Test
    func cancelLeavesAtOnceWhenNothingChanged() async {
        let dismissals = LockIsolated(0)
        let store = TestStore(initialState: state()) { EditShareFeature() } withDependencies: {
            $0.dismiss = DismissEffect { dismissals.withValue { $0 += 1 } }
        }

        await store.send(.cancelTapped)
        #expect(dismissals.value == 1)
    }

    @Test
    func anUntouchedExpiredShareLeavesWithoutAskingThoughSaveIsReady() async {
        let dismissals = LockIsolated(0)
        let expired = state(.editFixture(expiresAt: fixedNow.addingTimeInterval(-Constants.day)))
        #expect(expired.isSaveEnabled)
        #expect(!expired.hasEdits)
        #expect(!expired.isLeavingGuarded)
        let store = TestStore(initialState: expired) { EditShareFeature() } withDependencies: {
            $0.dismiss = DismissEffect { dismissals.withValue { $0 += 1 } }
        }

        await store.send(.cancelTapped)
        #expect(dismissals.value == 1)
    }

    @Test
    func cancelWithChangesAsksBeforeThrowingThemAway() async {
        let dismissals = LockIsolated(0)
        var initial = state()
        initial.label = "Bills"
        let store = TestStore(initialState: initial) { EditShareFeature() } withDependencies: {
            $0.dismiss = DismissEffect { dismissals.withValue { $0 += 1 } }
        }

        await store.send(.cancelTapped) { $0.isConfirmingDiscard = true }
        await store.send(.discardCancelled) { $0.isConfirmingDiscard = false }
        #expect(dismissals.value == 0)
        await store.send(.cancelTapped) { $0.isConfirmingDiscard = true }
        await store.send(.discardConfirmed) { $0.isConfirmingDiscard = false }
        #expect(dismissals.value == 1)
    }

    @Test
    func openingASpecificUsersShareLoadsThePeopleOnce() async {
        let jamie = User.jamieFixture
        let store = TestStore(
            initialState: state(.editFixture(target: .users, permittedUserIds: ["u2"]))
        ) {
            EditShareFeature()
        } withDependencies: {
            $0.filesClient.shareableUsers = { _ in [jamie] }
        }

        await store.send(.task) { $0.usersPhase = .loading }
        await store.receive(\.shareableUsersResponse.success) {
            $0.usersPhase = .loaded
            $0.shareableUsers = [jamie]
        }
        await store.send(.task)
        #expect(store.state.selectedUsers == [jamie])
    }

    @Test
    func aFailedPeopleLoadRetriesOnTheNextVisitAndLeavesNoStaleError() async {
        let jamie = User.jamieFixture
        let attempts = LockIsolated(0)
        let store = TestStore(
            initialState: state(.editFixture(target: .users, permittedUserIds: ["u2"]))
        ) {
            EditShareFeature()
        } withDependencies: {
            $0.filesClient.shareableUsers = { _ in
                attempts.withValue { $0 += 1 }
                if attempts.value == 1 {
                    throw FilesClientError.offline
                }
                return [jamie]
            }
        }

        await store.send(.task) { $0.usersPhase = .loading }
        await store.receive(\.shareableUsersResponse.failure) {
            $0.usersPhase = .failed(FilesClientError.offline.userMessage)
        }
        await store.send(.task) { $0.usersPhase = .loading }
        await store.receive(\.shareableUsersResponse.success) {
            $0.usersPhase = .loaded
            $0.shareableUsers = [jamie]
        }
        #expect(store.state.errorMessage == nil)
    }

    @Test
    func openingAnAnyoneShareLoadsNothing() async {
        let store = TestStore(initialState: state()) { EditShareFeature() }

        await store.send(.task)
    }
}
