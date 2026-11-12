import Foundation
import Localization
@testable import ShareUploads
import Testing
import UserNotifications

@Suite("Upload notifications")
struct UploadNotificationTests {
    private func outcome(uploaded: Int, failures: [FailedUpload] = [], destination: String = "Photos/2026") -> BatchOutcome {
        BatchOutcome(
            batchID: "BATCH", accountID: "https://files.example.com|phillip", host: "files.example.com",
            destination: destination, uploaded: uploaded, failures: failures
        )
    }

    private func english<T>(_ body: () -> T) -> T {
        LocalizationOverride.withLanguage("en", operation: body)
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
        #expect(lines[2] == "a.jpg, b.jpg, c.jpg, and 2 more")
    }

    private func names(_ count: Int) -> [String] {
        (1 ... count).map { "f\($0).jpg" }
    }

    @Test("The names are joined and the rest counted the way each language writes a list")
    func namesFollowTheLanguage() {
        func line(_ language: String, _ count: Int) -> String {
            LocalizationOverride.withLanguage(language) { UploadNotification.namesLine(names(count)) }
        }
        #expect(line("en", 1) == "f1.jpg")
        #expect(line("en", 2) == "f1.jpg and f2.jpg")
        #expect(line("en", 3) == "f1.jpg, f2.jpg, and f3.jpg")
        #expect(line("en", 6) == "f1.jpg, f2.jpg, f3.jpg, and 3 more")
        #expect(line("ja", 3) == "f1.jpg、f2.jpg、f3.jpg")
        #expect(line("ja", 6) == "f1.jpg、f2.jpg、f3.jpg、ほか 3 件")
        #expect(line("ru", 3) == "f1.jpg, f2.jpg и f3.jpg")
        #expect(line("ru", 6) == "f1.jpg, f2.jpg, f3.jpg и ещё 3")
        #expect(line("ar", 2) == "\u{2068}f1.jpg\u{2069} و\u{2068}f2.jpg\u{2069}")
        #expect(line("ar", 5) == "\u{2068}f1.jpg\u{2069} و\u{2068}f2.jpg\u{2069} و\u{2068}f3.jpg\u{2069} و2 أخرى")
    }

    @Test("The count of further names is translated in every language, with the number in it")
    func moreNamesTranslated() {
        let english = english { L10n.ShareUpload.notificationMoreNames(7) }
        #expect(english == "7 more")
        for language in LocalizationOverride.supportedLanguages where language != "en" {
            let text = LocalizationOverride.withLanguage(language) { L10n.ShareUpload.notificationMoreNames(7) }
            #expect(text != english, "\(language) still reads English")
            #expect(!text.hasPrefix("shareUpload."), "\(language) fell back to its key")
        }
    }

    @Test("Arabic quotes the folder with guillemets, as the other Arabic strings do")
    func arabicQuotes() {
        for count in [0, 1, 2, 3, 11, 100] {
            let text = LocalizationOverride.withLanguage("ar") { L10n.ShareUpload.notificationDoneBody(count, "Photos") }
            #expect(text.contains("«") && text.contains("»") && text.contains("Photos"), Comment(rawValue: text))
            #expect(!text.contains("”") && !text.contains("“"), Comment(rawValue: text))
        }
    }

    @Test("The user info carries the batch, its account and its folder, never file names or the server")
    func userInfo() {
        let failures = [FailedUpload(name: "a.jpg", cause: .serverFull)]
        let failed = UploadNotification(outcome: outcome(uploaded: 1, failures: failures)).userInfo
        let clean = UploadNotification(outcome: outcome(uploaded: 1)).userInfo
        for info in [failed, clean] {
            #expect(info.count == 3)
            #expect(info[UploadNotificationKey.batchID] as? String == "BATCH")
            #expect(info[UploadNotificationKey.accountID] as? String == "https://files.example.com|phillip")
            #expect(info[UploadNotificationKey.destination] as? String == "Photos/2026")
        }
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
            let text = LocalizationOverride.withLanguage(language) { L10n.ShareUpload.notificationHiddenPreview }
            #expect(!text.isEmpty && !text.hasPrefix("shareUpload."), "\(language)")
        }
    }

    @Test("Every cause has text in the other languages too, with the count in it")
    func translated() {
        for language in LocalizationOverride.supportedLanguages {
            for cause in UploadFailureCause.allCases {
                let text = LocalizationOverride.withLanguage(language) { UploadNotification.causeText(cause, count: 3) }
                #expect(text.contains("3"), "\(language) \(cause)")
                #expect(!text.hasPrefix("shareUpload."), "\(language) \(cause) fell back to its key")
            }
        }
    }

    // MARK: Posting

    @Test("A finished batch is posted under its batch id, so a retry's result replaces the earlier notification")
    func postsOneRequestPerBatch() {
        let center = RecordingCenter()
        let failures = [FailedUpload(name: "a.jpg", cause: .network)]

        english { UploadNotifier.posting(to: center.center).batchFinished(outcome(uploaded: 1, failures: failures)) }
        english { UploadNotifier.posting(to: center.center).batchFinished(outcome(uploaded: 2)) }

        let requests = center.requests
        #expect(requests.map(\.identifier) == ["BATCH", "BATCH"])
        #expect(requests[0].content.title == "Some files didn't upload")
        #expect(requests[0].content.categoryIdentifier == UploadNotificationIdentifier.failedCategory)
        #expect(requests[0].content.subtitle == "files.example.com")
        #expect(requests[0].content.threadIdentifier == "https://files.example.com|phillip")
        #expect(requests[0].content.userInfo[UploadNotificationKey.batchID] as? String == "BATCH")
        #expect(requests[1].content.title == "Upload finished")
        #expect(requests[1].content.body == "2 files uploaded to “2026”.")
        #expect(requests[1].content.categoryIdentifier == UploadNotificationIdentifier.doneCategory)
        #expect(center.categorySets.count == 2, "the categories are registered before each post")
    }

    @Test("A retry that could not start says what to do, depending on why")
    func postsTheRetryFailure() {
        let center = RecordingCenter()

        english { UploadNotifier.postRetryFailed(.nothingToSend, using: center.center) }
        english { UploadNotifier.postRetryFailed(.needsSignIn, using: center.center) }

        let requests = center.requests
        #expect(requests.map(\.identifier) == Array(repeating: UploadNotificationIdentifier.retryFailureNotification, count: 2))
        #expect(requests.map(\.content.title) == ["Couldn't retry", "Couldn't retry"])
        #expect(requests.map(\.content.body) == [
            "Open NextExplorer and share the files again.",
            "Sign in to NextExplorer, then tap Retry again.",
        ])
    }

    // MARK: Delegate

    @Test("Retry restarts the batch, a tap opens the folder, a dismissal does nothing; no file is deleted by any")
    func decisions() {
        let info: [AnyHashable: Any] = [
            UploadNotificationKey.batchID: "BATCH",
            UploadNotificationKey.accountID: "https://files.example.com|phillip",
            UploadNotificationKey.destination: "Files/Documents",
        ]
        #expect(
            UploadNotificationHandler.decision(actionIdentifier: UploadNotificationIdentifier.retryAction, userInfo: info)
                == .retry(batchID: "BATCH")
        )
        #expect(
            UploadNotificationHandler.decision(actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: info)
                == .open(accountID: "https://files.example.com|phillip", folder: "Files/Documents")
        )
        #expect(UploadNotificationHandler.decision(actionIdentifier: UNNotificationDismissActionIdentifier, userInfo: info) == .ignore)
        #expect(UploadNotificationHandler.decision(actionIdentifier: "other", userInfo: info) == .ignore)
    }

    @Test("A notification posted before folders were included only opens the app")
    func olderNotificationOnlyOpens() {
        let info: [AnyHashable: Any] = [UploadNotificationKey.batchID: "BATCH"]
        #expect(UploadNotificationHandler.decision(actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: info) == .ignore)
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

    @Test("A system completion handler called from a background thread still runs on the main thread")
    func completionRunsOnMain() async {
        let ranOnMain = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                MainThreadCompletion { continuation.resume(returning: Thread.isMainThread) }.call()
            }
        }
        #expect(ranOnMain)
    }
}
