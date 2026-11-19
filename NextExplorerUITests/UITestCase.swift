import CoreModels
import Localization
import XCTest

/// Base class for the critical path UI tests. Launches the app against the fully mocked,
/// backend free dependency graph wired in `AppFeature.prepareUITestDependencies`, driven
/// entirely through the launch environment so no network, keychain or disk state is touched.
class UITestCase: XCTestCase {
    /// Names the mock backend serves; the browse and search names come from `UITestFixture`,
    /// which the mock app reads too.
    enum Fixture {
        static let folder = UITestFixture.Folder.documents.name
        static let file = UITestFixture.File.notes.name
        /// An image file in the root fixture listing.
        static let imageFile = UITestFixture.File.vacation.name
        static let searchQuery = UITestFixture.File.vacation.stem
        /// Part of `file`'s name, so it is among the search results.
        static let fileSearchTerm = UITestFixture.File.notes.stem
        /// Stable first hit the mocked search returns.
        static let searchHit = UITestFixture.File.quarterlyReport.name
        /// The shortest query the server searches (mirrors `FilesClient.minimumSearchTermLength`).
        static let minimumSearchLength = 3
        /// Image hit the mocked search returns.
        static let imageSearchHit = UITestFixture.File.beach.name
        /// Hit only a search from the root returns.
        static let widerSearchHit = UITestFixture.File.archiveNotes.name
        /// A folder the mocked backend rejects, driving the create failure path.
        static let failingFolderName = UITestFixture.failingFolderName
        /// A folder used as a long pressable favorite target (folders only can be favorited).
        static let folderAlt = UITestFixture.Folder.photos.name
        typealias Credential = UITestFixture.Credential
        /// A sign in name the mocked login answers with "send a code", the code and recovery code
        /// it then accepts.
        static let secondFactorIdentifier = Credential.secondFactorUser.rawValue
        /// A sign in name the mocked login refuses as wrong credentials.
        static let rejectedIdentifier = Credential.rejectedUser.rawValue
        static let validCode = Credential.validCode.rawValue
        static let wrongCode = Credential.wrongCode.rawValue
        static let validRecoveryCode = Credential.recoveryCode.rawValue
        /// The password the mocked account routes accept.
        static let accountPassword = Credential.password.rawValue
        static let wrongPassword = Credential.wrongPassword.rawValue
        /// The server address and sign in name the mocked login accepts.
        static let serverHost = UITestFixture.Host.primary.rawValue
        static let accountIdentifier = UITestFixture.SignedInAccount.email.rawValue
        /// A second server, for adding another account.
        static let otherServerHost = UITestFixture.Host.other.rawValue
    }

    enum Auth: String {
        case loggedOut
        case loggedIn
        case expired
    }

    enum Scenario: String {
        case normal
        case empty
        case error
        case sessionExpired
        case gallery
        case slowOperations
    }

    #if os(macOS)
        /// Puts back the keyboard layout `KeyboardLayout.useUS` replaced for this test.
        private var restoreKeyboardLayout: (() -> Void)?
    #endif

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        #if os(macOS)
            restoreKeyboardLayout = KeyboardLayout.useUS()
        #endif
    }

    override func tearDown() {
        #if os(macOS)
            restoreKeyboardLayout?()
            restoreKeyboardLayout = nil
        #endif
        super.tearDown()
    }

    /// Taps a tab bar tab, waiting until a sentinel element on that tab appears. Tab switching in
    /// XCUITest can drop the first tap under load, so it retries the tap once before failing.
    func selectTab(
        _ tab: XCUIElement,
        until sentinel: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(tab.waitToAppear(UITestTimeout.standard, "Tab should exist", file: file, line: line))
        // A tap can land while the app is still remounting (adding an account rebuilds it), so a
        // few tries before the final wait.
        for _ in 0 ..< UITestTimeout.tabTapAttempts {
            #if os(iOS)
                declineSavePasswordIfShown(in: XCUIApplication())
            #endif
            tapCenter(of: tab)
            if sentinel.appears(within: UITestTimeout.short) {
                return
            }
        }
        XCTAssertTrue(sentinel.waitToAppear(
            UITestTimeout.standard,
            "Tab content should appear",
            file: file,
            line: line
        ))
    }

    /// Taps the element's center by coordinate. On iPhone Duo the tabs sit in the vertical bar and
    /// XCUITest treats the lowest ones as needing a scroll into view; the accessibility scroll it
    /// attempts never returns, hanging the test. A coordinate tap skips that step.
    /// The frame is read once and tapped as an absolute point from the app root, so the element
    /// is not re-resolved mid tap (an element coordinate can come back infinite under load).
    func tapCenter(
        of element: XCUIElement,
        in app: XCUIApplication = XCUIApplication(),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // The frame can still be empty while the bar lays out; never fall back to `tap()`, which
        // is the hanging scroll path.
        let hasFrame = NSPredicate { object, _ in
            guard let frame = (object as? XCUIElement)?.frame else { return false }
            return !frame.isEmpty && !frame.isInfinite
        }
        _ = waitUntil(hasFrame, on: element, timeout: UITestTimeout.short)
        let frame = element.frame
        guard !frame.isEmpty, !frame.isInfinite else {
            XCTFail("\(element) has no on screen frame to tap", file: file, line: line)
            return
        }
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
    }

    /// Runs a gesture that should open a menu (a long press or a menu button tap), then waits for
    /// a sentinel item in that menu. XCUITest occasionally drops the gesture, so it retries once.
    func openMenu(_ open: () -> Void, until sentinel: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        open()
        // Two windows before retrying: a menu that opens slowly would otherwise get a second tap
        // on its trigger while already open, and that trigger is no longer hittable.
        if sentinel.appears(within: UITestTimeout.short) || sentinel.appears(within: UITestTimeout.short) {
            return
        }
        open()
        XCTAssertTrue(sentinel.waitToAppear(UITestTimeout.standard, "Menu did not open", file: file, line: line))
    }

    /// Scrolls the app up until `element` exists or the swipe budget runs out, for rows a lazy
    /// list only materializes once near the viewport. Returns whether it appeared.
    @discardableResult
    func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) -> Bool {
        var swipes = 0
        // Reachable, not just present: a lazy list materializes a row while it is still under the tab
        // bar, where a tap would land on the bar instead.
        while !(element.exists && element.isHittable), swipes < maxSwipes {
            #if os(iOS)
                swipeUp(in: scrollContainer(in: app))
            #else
                app.scroll(byDeltaX: 0, deltaY: -Self.macScrollStep)
            #endif
            swipes += 1
            // The row appears once the list settles after the swipe, so look again before swiping on.
            _ = element.appears(within: UITestTimeout.pollInterval * 2)
        }
        return element.exists
    }

    #if os(iOS)
        /// The list on screen, so a swipe starts inside it and never on the tab bar floating above it.
        /// The widest one, so on iPad it is the screen's content and not the sidebar beside it: the
        /// content list sits under the sidebar there, so it never reads as hittable and is dragged by
        /// a point in its middle instead.
        private func scrollContainer(in app: XCUIApplication) -> XCUIElement {
            for query in [app.collectionViews, app.tables, app.scrollViews] {
                let shown = query.allElementsBoundByIndex.filter { $0.exists && !$0.frame.isEmpty }
                if let widest = shown.max(by: { $0.frame.width < $1.frame.width }) {
                    return widest
                }
            }
            return app
        }

        /// Drags the container up by a point in its middle, clear of a bar floating at the bottom.
        private func swipeUp(in container: XCUIElement) {
            let start = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let end = container.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            start.press(forDuration: UITestTimeout.dragPress, thenDragTo: end)
        }

        /// iOS's Save Password prompt can come up a moment after a sign in ends and take the next
        /// tap; declined here if it is up, without waiting for it.
        func declineSavePasswordIfShown(in app: XCUIApplication) {
            let notNow = app.alerts.buttons[UITestCase.savePasswordDeclineTitle].firstMatch
            if notNow.exists {
                notNow.tap()
                _ = notNow.waitToVanish(UITestTimeout.short)
            }
        }
    #endif

    /// The button iOS's Save Password prompt offers to decline it (the simulator runs in English).
    static let savePasswordDeclineTitle = "Not Now"

    /// Launches the app with the mock graph enabled. `auth` picks the session state the app
    /// restores on cold launch, `scenario` picks the shape of the mocked file data.
    /// Default CoreAnimation speed multiplier for the suite's SwiftUI animations (flood, focus,
    /// zoom), so their code still runs but finishes near instantly. 0 leaves them at real time.
    static let fastAnimationSpeed: Double = 12

    /// How far one `scrollTo` step scrolls on the Mac, which has no swipe.
    static let macScrollStep: CGFloat = 300

    @discardableResult
    func launchApp(
        auth: Auth = .loggedIn,
        scenario: Scenario = .normal,
        animationSpeed: Double = UITestCase.fastAnimationSpeed,
        landscape: Bool = false,
        legacyDownloads: Bool = false,
        searchOffline: Bool = false,
        offlineLaunch: Bool = false,
        failing: Set<UITestArea> = [],
        empty: Set<UITestArea> = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        if !failing.isEmpty {
            app.launchEnvironment[UITestLaunchKey.failingAreas.rawValue] = UITestArea.launchValue(failing)
        }
        if !empty.isEmpty {
            app.launchEnvironment[UITestLaunchKey.emptyAreas.rawValue] = UITestArea.launchValue(empty)
        }
        if legacyDownloads {
            app.launchEnvironment[UITestLaunchKey.legacyDownloads.rawValue] = UITestLaunchKey.on
        }
        if searchOffline {
            app.launchEnvironment[UITestLaunchKey.searchOffline.rawValue] = UITestLaunchKey.on
        }
        if offlineLaunch {
            app.launchEnvironment[UITestLaunchKey.offlineLaunch.rawValue] = UITestLaunchKey.on
        }
        app.launchEnvironment[UITestLaunchKey.mock.rawValue] = UITestLaunchKey.on
        app.launchEnvironment[UITestLaunchKey.auth.rawValue] = auth.rawValue
        app.launchEnvironment[UITestLaunchKey.scenario.rawValue] = scenario.rawValue
        // UIKit animations (pushes, sheets, alerts, context menus) are always off. A context menu
        // animating beside a sped up window never reported done, so XCUITest waited its full
        // minute for the app to idle on every menu open and close (146 s for a rename test, 25 s
        // now). SwiftUI animations still run, sped up, so their code is exercised. iPhone Duo (two
        // screens) skips the speed up: there a sped up layer left the idle wait hanging too.
        app.launchEnvironment[UITestLaunchKey.disableAnimations.rawValue] = UITestLaunchKey.on
        if animationSpeed > 0, XCUIScreen.screens.count < 2 {
            app.launchEnvironment[UITestLaunchKey.animationSpeed.rawValue] = String(animationSpeed)
        }
        if landscape {
            app.launchEnvironment[UITestLaunchKey.orientation.rawValue] = UITestLaunchKey.landscape
        }
        // Force English so localized visible text the tests match on is deterministic.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        #if os(macOS)
            // On a CI runner the launched app is not always frontmost, and an inactive app closes a
            // popover at once and can drop a right click: bring it forward before any test acts.
            app.activate()
            XCTAssertTrue(
                waitUntil(
                    NSPredicate(format: "state == %d", XCUIApplication.State.runningForeground.rawValue),
                    on: app
                ),
                "The app should be frontmost"
            )
        #endif
        return app
    }
}

/// Shared wait budgets so every test uses the same timeouts rather than sprinkling literals.
enum UITestTimeout {
    /// The normal budget for something to appear once an action has kicked off an async load.
    static let standard: TimeInterval = 10
    /// A tighter budget used when asserting something should NOT appear, so a negative check
    /// doesn't stall the suite.
    static let short: TimeInterval = 3
    /// How often `appears(within:)` looks again.
    static let pollInterval: TimeInterval = 0.25
    /// Taps `selectTab` tries before its final wait.
    static let tabTapAttempts = 3
    /// How long a scroll drag holds before it moves: short enough to read as a swipe, not a long press.
    static let dragPress: TimeInterval = 0.05
}

/// Waits until `predicate` holds for `object` (an element or a query) and returns whether it did,
/// without asserting. Waits on a condition, never for a fixed time.
/// The note over a listing shown from a saved copy ("Showing a saved copy from …"), matched on its fixed part.
func savedCopyNote(in app: XCUIApplication) -> XCUIElement {
    let fixedPart = L10n.Browse.offlineBannerDetail("").trimmingCharacters(in: .whitespaces)
    // A Mac text exposes its words as the value, an iPhone one as the label.
    return app.staticTexts
        .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", fixedPart, fixedPart))
        .firstMatch
}

func waitUntil(_ predicate: NSPredicate, on object: Any, timeout: TimeInterval = UITestTimeout.standard) -> Bool {
    XCTWaiter()
        .wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: object)], timeout: timeout) == .completed
}

extension XCUIElement {
    /// Waits for the element to exist, failing the test with a clear message otherwise.
    @discardableResult
    func waitToAppear(
        _ timeout: TimeInterval = UITestTimeout.standard,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let appeared = waitForExistence(timeout: timeout)
        XCTAssertTrue(appeared, message.isEmpty ? "Expected \(self) to appear" : message, file: file, line: line)
        return appeared
    }

    /// Returns whether the element exists within the budget, without asserting. Use for negative
    /// checks (`XCTAssertFalse(element.appears(within:))`).
    func appears(within timeout: TimeInterval = UITestTimeout.short) -> Bool {
        // Polled rather than `waitForExistence`: a timed out wait makes XCTest collect failure
        // triage diagnostics (about 20 s on a CI runner) even when not appearing is the answer.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(UITestTimeout.pollInterval))
        }
        return exists
    }

    /// Waits for the element to stop existing (e.g. a sheet dismissing on success).
    @discardableResult
    func waitToVanish(_ timeout: TimeInterval = UITestTimeout.standard) -> Bool {
        waitUntil(NSPredicate(format: "exists == false"), on: self, timeout: timeout)
    }

    /// Returns whether the element has keyboard focus within the budget, without asserting.
    func isFocused(within timeout: TimeInterval = UITestTimeout.standard) -> Bool {
        waitUntil(NSPredicate(format: "hasKeyboardFocus == true"), on: self, timeout: timeout)
    }

    /// Returns whether the element is enabled within the budget, without asserting.
    func isEnabled(within timeout: TimeInterval = UITestTimeout.standard) -> Bool {
        waitUntil(NSPredicate(format: "isEnabled == true"), on: self, timeout: timeout)
    }

    /// Waits until the element is hittable and its frame stays the same between two checks, so a
    /// tap does not land while it is still sliding in (a system sheet animates even with the
    /// app's animations off). Returns whether it settled, without asserting.
    @discardableResult
    func waitForFrameToSettle(_ timeout: TimeInterval = UITestTimeout.standard) -> Bool {
        var lastFrame = CGRect.null
        let settled = NSPredicate { object, _ in
            guard let element = object as? XCUIElement, element.exists, element.isHittable else {
                lastFrame = .null
                return false
            }
            defer { lastFrame = element.frame }
            return element.frame == lastFrame
        }
        return waitUntil(settled, on: self, timeout: timeout)
    }

    /// Waits for the element to become hittable, failing otherwise.
    @discardableResult
    func waitToBeHittable(
        _ timeout: TimeInterval = UITestTimeout.standard,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let ok = waitUntil(NSPredicate(format: "isHittable == true"), on: self, timeout: timeout)
        XCTAssertTrue(ok, "Expected \(self) to be hittable", file: file, line: line)
        return ok
    }

    /// Long presses to surface a row's context menu.
    func longPress(_ duration: TimeInterval = 1.1) {
        press(forDuration: duration)
    }

    /// Clears any existing text then types the given string. Assumes the field is tappable.
    func clearAndType(_ text: String) {
        tap()
        // An already focused field keeps the caret where the tap landed, possibly mid text, which
        // left a tail behind the deletes ("__uitest_fail__2"). Park it at the trailing edge first.
        coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if let existing = value as? String, !existing.isEmpty {
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            typeText(deletes)
        }
        typeText(text)
    }
}

#if os(macOS)
    /// The Mac clicks where iOS taps, so the shared helpers and screens read the same on both.
    extension XCUIElement {
        func tap() {
            click()
        }
    }

    extension XCUICoordinate {
        func tap() {
            click()
        }
    }
#endif
