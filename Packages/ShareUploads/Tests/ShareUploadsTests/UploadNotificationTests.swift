import Foundation
import Localization
@testable import ShareUploads
import Testing
import UserNotifications

@Suite("Upload notifications", .serialized)
struct UploadNotificationTests {
    private func outcome(uploaded: Int, failures: [FailedUpload] = [], destination: String = "Photos/2026") -> BatchOutcome {
        BatchOutcome(
            batchID: "BATCH", accountID: "https://files.example.com|phillip", host: "files.example.com",
            destination: destination, uploaded: uploaded, failures: failures
        )
    }

    private func english<T>(_ body: () -> T) -> T {
        LocalizationOverride.apply("en")
        defer { LocalizationOverride.apply(nil) }
        return body()
    }

    @Test("A clean batch says where the files went and counts them")
    func allUploaded() {
        let one = english { UploadNotification(outcome: outcome(uploaded: 1)) }
        let many = english { UploadNotification(outcome: outcome(uploaded: 3)) }
        #expect(one.title == "Upload finished")
        #expect(one.body == "1 file uploaded to “2026”.")
        #expect(many.body == "3 files uploaded to “2026”.")
        #expect(!many.hasFailures)
        #expect(many.subtitle == "files.example.com")
    }

    @Test("The title says some files failed only when others succeeded, and all failed when none did")
    func titles() {
        let failure = [FailedUpload(name: "a.jpg", cause: .network)]
        let some = english { UploadNotification(outcome: outcome(uploaded: 2, failures: failure)) }
        let none = english { UploadNotification(outcome: outcome(uploaded: 0, failures: failure)) }
        #expect(some.title == "Some files didn't upload")
        #expect(none.title == "Upload failed")
    }

    @Test("Each cause gets its own advice, with the failed names listed")
    func causeAwareBody() {
        func body(_ cause: UploadFailureCause, count: Int = 1) -> String {
            let failures = (1 ... count).map { FailedUpload(name: "f\($0).jpg", cause: cause) }
            return english { UploadNotification(outcome: outcome(uploaded: 0, failures: failures)).body }
        }
        #expect(body(.unauthorized) == "1 file wasn't uploaded. Sign in again, then retry.\nf1.jpg")
        #expect(body(.forbidden).contains("permission"))
        #expect(body(.serverFull).contains("out of storage"))
        #expect(body(.network).contains("connection failed"))
        #expect(body(.other) == "1 file couldn't be uploaded.\nf1.jpg")
        #expect(body(.network, count: 2).hasPrefix("2 files weren't uploaded."))
    }

    @Test("Mixed causes get one line each and a long name list is cut with a count")
    func mixedCauses() {
        let failures = [
            FailedUpload(name: "a.jpg", cause: .network),
            FailedUpload(name: "b.jpg", cause: .unauthorized),
            FailedUpload(name: "c.jpg", cause: .network),
            FailedUpload(name: "d.jpg", cause: .network),
            FailedUpload(name: "e.jpg", cause: .network),
        ]
        let notification = english { UploadNotification(outcome: outcome(uploaded: 0, failures: failures)) }
        let lines = notification.body.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("1 file wasn't uploaded. Sign in again"))
        #expect(lines[1].hasPrefix("4 files weren't uploaded."))
        #expect(lines[2] == "a.jpg, b.jpg, c.jpg and 2 more")
        #expect(notification.primaryCause == .network)
    }

    @Test("On a tie the cause the user can fix soonest is primary")
    func primaryCauseTie() {
        let failures = [FailedUpload(name: "a", cause: .network), FailedUpload(name: "b", cause: .unauthorized)]
        #expect(UploadNotification.primaryCause(of: failures) == .unauthorized)
        #expect(UploadNotification.primaryCause(of: []) == nil)
    }

    @Test("The user info carries only the batch id, nothing about the files or the server")
    func userInfo() {
        let failures = [FailedUpload(name: "a.jpg", cause: .serverFull)]
        let failed = UploadNotification(outcome: outcome(uploaded: 1, failures: failures)).userInfo
        let clean = UploadNotification(outcome: outcome(uploaded: 1)).userInfo
        #expect(failed.count == 1)
        #expect(failed[UploadNotificationKey.batchID] as? String == "BATCH")
        #expect(clean.count == 1)
        #expect(clean[UploadNotificationKey.batchID] as? String == "BATCH")
    }

    @Test("Both categories hide the body behind a placeholder when previews are hidden")
    func categoriesHidePreviews() {
        let categories = UploadNotifier.categories()
        #expect(Set(categories.map(\.identifier)) == [
            UploadNotificationIdentifier.failedCategory, UploadNotificationIdentifier.doneCategory,
        ])
        for category in categories {
            #expect(!category.hiddenPreviewsBodyPlaceholder.isEmpty)
            #expect(category.hiddenPreviewsBodyPlaceholder == english { L10n.ShareUpload.notificationHiddenPreview })
        }
        #expect(categories.first { $0.identifier == UploadNotificationIdentifier.failedCategory }?.actions.count == 1)
        #expect(categories.first { $0.identifier == UploadNotificationIdentifier.doneCategory }?.actions.isEmpty == true)
    }

    @Test("The hidden preview text is translated in every language")
    func hiddenPreviewTranslated() {
        for language in LocalizationOverride.supportedLanguages {
            LocalizationOverride.apply(language)
            defer { LocalizationOverride.apply(nil) }
            let text = L10n.ShareUpload.notificationHiddenPreview
            #expect(!text.isEmpty && !text.hasPrefix("shareUpload."), "\(language)")
        }
    }

    @Test("Every cause has text in the other languages too, with the count in it")
    func translated() {
        for language in LocalizationOverride.supportedLanguages {
            LocalizationOverride.apply(language)
            defer { LocalizationOverride.apply(nil) }
            for cause in UploadFailureCause.allCases {
                let text = UploadNotification.causeText(cause, count: 3)
                #expect(text.contains("3"), "\(language) \(cause)")
                #expect(!text.hasPrefix("shareUpload."), "\(language) \(cause) fell back to its key")
            }
        }
    }

    // MARK: Delegate

    @Test("Banners show while the app is frontmost")
    func foregroundPresentation() {
        #expect(UploadNotificationHandler.foregroundOptions == [.banner, .list])
    }

    @Test("Retry restarts the batch; a dismissal and a tap do nothing, so no file is ever deleted by them")
    func decisions() {
        let info: [AnyHashable: Any] = [UploadNotificationKey.batchID: "BATCH"]
        #expect(
            UploadNotificationHandler.decision(actionIdentifier: UploadNotificationIdentifier.retryAction, userInfo: info)
                == .retry(batchID: "BATCH")
        )
        #expect(UploadNotificationHandler.decision(actionIdentifier: UNNotificationDismissActionIdentifier, userInfo: info) == .ignore)
        #expect(UploadNotificationHandler.decision(actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: info) == .ignore)
        #expect(UploadNotificationHandler.decision(actionIdentifier: "other", userInfo: info) == .ignore)
    }

    @Test("A notification without its batch id is ignored")
    func incompleteUserInfo() {
        #expect(UploadNotificationHandler.decision(actionIdentifier: UploadNotificationIdentifier.retryAction, userInfo: [:]) == .ignore)
        #expect(UploadNotificationHandler.decision(actionIdentifier: UNNotificationDismissActionIdentifier, userInfo: [:]) == .ignore)
    }

    // MARK: Permission

    private final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [UNAuthorizationOptions] = []

        var options: [UNAuthorizationOptions] {
            lock.withLock { recorded }
        }

        func add(_ options: UNAuthorizationOptions) {
            lock.withLock { recorded.append(options) }
        }
    }

    private func authorization(
        status: UNAuthorizationStatus, fullFails: Bool = false, requests: Requests
    ) -> NotificationAuthorization {
        NotificationAuthorization(
            status: { status },
            request: { options in
                requests.add(options)
                if fullFails, !options.contains(.provisional) {
                    throw CocoaError(.featureUnsupported)
                }
                return true
            }
        )
    }

    @Test("Full permission is asked for once, when nothing was asked before")
    func asksFullPermission() async {
        let requests = Requests()
        await UploadNotifier.requestPermission(using: authorization(status: .notDetermined, requests: requests))
        #expect(requests.options == [[.alert, .sound]])
    }

    @Test("An earlier answer, quiet or not, is never asked again")
    func neverAsksTwice() async {
        var answered: [UNAuthorizationStatus] = [.authorized, .denied, .provisional]
        #if os(iOS)
            answered.append(.ephemeral)
        #endif
        for status in answered {
            let requests = Requests()
            await UploadNotifier.requestPermission(using: authorization(status: status, requests: requests))
            #expect(requests.options.isEmpty, "\(status.rawValue)")
        }
    }

    @Test("Where the full prompt cannot be shown the quiet permission is the fallback")
    func provisionalFallback() async {
        let requests = Requests()
        await UploadNotifier.requestPermission(using: authorization(status: .notDetermined, fullFails: true, requests: requests))
        #expect(requests.options == [[.alert, .sound], [.alert, .provisional]])
    }
}
