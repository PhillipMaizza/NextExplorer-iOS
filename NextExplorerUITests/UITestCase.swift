import XCTest

/// Base class for the critical path UI tests. Launches the app against the fully mocked,
/// backend free dependency graph wired in `AppFeature.prepareUITestDependencies`, driven
/// entirely through the launch environment so no network, keychain or disk state is touched.
class UITestCase: XCTestCase {
    /// Names the mock backend serves, mirroring `FileItem.previewItems` in the files client and
    /// the search echo in `UITestSupport`. Test owned data, kept here as the single source so a
    /// fixture rename touches one place.
    enum Fixture {
        static let folder = "Documents"
        static let file = "notes.txt"
        /// An image file in the root fixture listing.
        static let imageFile = "vacation.jpg"
        static let searchQuery = "vacation"
        /// Stable first hit the mocked search returns (mirrors `UITestSupport.searchHitName`).
        static let searchHit = "Quarterly Report.txt"
        /// Image hit the mocked search returns (mirrors `UITestSupport.imageSearchHitName`).
        static let imageSearchHit = "Beach.jpg"
        /// A folder the mocked backend rejects, driving the create failure path (mirrors
        /// `UITestSupport.failingFolderName`).
        static let failingFolderName = "__uitest_fail__"
        /// A folder used as a long pressable favorite target (folders only can be favorited).
        static let folderAlt = "Photos"
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
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Taps a tab bar tab, waiting until a sentinel element on that tab appears. Tab switching in
    /// XCUITest can drop the first tap under load, so it retries the tap once before failing.
    func selectTab(_ tab: XCUIElement, until sentinel: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(tab.waitToAppear(UITestTimeout.standard, "Tab should exist", file: file, line: line))
        tab.tap()
        if !sentinel.appears(within: UITestTimeout.short) {
            tab.tap()
            XCTAssertTrue(sentinel.waitToAppear(UITestTimeout.standard, "Tab content should appear", file: file, line: line))
        }
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
        while !element.exists, swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists
    }

    /// Launches the app with the mock graph enabled. `auth` picks the session state the app
    /// restores on cold launch, `scenario` picks the shape of the mocked file data.
    /// Default CoreAnimation speed multiplier for the suite. Scales every UIKit and SwiftUI
    /// animation (flood/focus/zoom/comet included) uniformly, so transition code still runs but
    /// finishes near instantly. Real time is 1.0; 0 hard freezes UIKit animations.
    static let fastAnimationSpeed: Double = 12

    @discardableResult
    func launchApp(auth: Auth = .loggedIn, scenario: Scenario = .normal, animationSpeed: Double = UITestCase.fastAnimationSpeed) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MOCK"] = "1"
        app.launchEnvironment["UITEST_AUTH"] = auth.rawValue
        app.launchEnvironment["UITEST_SCENARIO"] = scenario.rawValue
        // A speed multiplier keeps transitions running (so their code is exercised) but collapses
        // their duration; 0 falls back to hard freezing UIKit animations.
        if animationSpeed > 0 {
            app.launchEnvironment["UITEST_ANIM_SPEED"] = String(animationSpeed)
        } else {
            app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        }
        // Force English so localized visible text the tests match on is deterministic.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
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
}

extension XCUIElement {
    /// Waits for the element to exist, failing the test with a clear message otherwise.
    @discardableResult
    func waitToAppear(_ timeout: TimeInterval = UITestTimeout.standard, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let appeared = waitForExistence(timeout: timeout)
        XCTAssertTrue(appeared, message.isEmpty ? "Expected \(self) to appear" : message, file: file, line: line)
        return appeared
    }

    /// Returns whether the element exists within the budget, without asserting. Use for negative
    /// checks (`XCTAssertFalse(element.appears(within:))`).
    func appears(within timeout: TimeInterval = UITestTimeout.short) -> Bool {
        waitForExistence(timeout: timeout)
    }

    /// Waits for the element to stop existing (e.g. a sheet dismissing on success).
    @discardableResult
    func waitToVanish(_ timeout: TimeInterval = UITestTimeout.standard) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits for the element to become hittable, failing otherwise.
    @discardableResult
    func waitToBeHittable(_ timeout: TimeInterval = UITestTimeout.standard, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let hittable = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: hittable, object: self)
        let ok = XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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
        if let existing = value as? String, !existing.isEmpty {
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            typeText(deletes)
        }
        typeText(text)
    }
}
