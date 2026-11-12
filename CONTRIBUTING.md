# Contributing to NextExplorer for iPhone, iPad and Mac

Thanks for taking a look. This guide covers how the project is built and the conventions every change follows. They are not stylistic preferences; they keep the app fast, private and account-safe, and a PR that follows them is far quicker to review.

## Getting set up

1. Install Xcode 27 (what CI builds with; the code needs the iOS and macOS 26 SDKs or later).
2. Fork and clone the repo, then open `NextExplorer.xcodeproj`.
3. Swift Package Manager resolves dependencies on first build. No extra tooling.
4. Build and run the **NextExplorer** scheme on an iOS 18+ simulator or device, or on **My Mac** (macOS 15+). To exercise the app end to end you need a compatible self-hosted server and an account on it.

## Source of truth

The backend contract is authoritative. Never invent an API shape, a limit or a validation rule: mirror what the server actually returns and enforces. Validators on device exist to match the backend, not to guess at one.

## Proposing a change

1. Open an issue first for anything non-trivial, so the direction is agreed before code is written. Bug reports and feature requests use the issue forms, which ask for what a fix needs: steps to reproduce, expected and observed behavior, app, system and server versions, and how the app reaches the server.
2. Branch from `main`. Branches are named `feature/NXTIOS-short-slug` (for example `feature/NXTIOS-grid-spacing`). No bare descriptive branch names.
3. Keep the change on the one working branch and open a pull request against `main` when it is ready. Describe what changed and why, and reference the issue.

## Architecture

- Native iOS 18+ and macOS 15+ from one target, SwiftUI, and [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) (`@Reducer`, `@ObservableState`, `TestStore`).
- Follow the existing architecture and preserve dependency direction. Reuse existing infrastructure and TCA dependencies rather than adding parallel ones. No unrelated refactors in a feature PR.

### State modelling

- Model each screen or data load as a single lifecycle phase: `DataPhase` (`idle` / `loading` / `loaded` / `failed`). Derive `hasLoaded`, `errorMessage` and `shouldLoadOnAppear` from the phase. Do not spread one lifecycle across `isLoading` + `hasLoaded` + `errorMessage` booleans. A single in-flight flag for a mutation (like `isSaving`) is fine; two or more booleans encoding one lifecycle is not.
- Model errors by meaning (validation, auth, expired session, rate limit, network, server, decoding). Never surface a raw technical error to the user.

### Concurrency

- Keep heavy work off the main actor. Image decode and downsample, large file and JSON reads, Markdown / tree-sitter / regex parsing, and PDF or archive work run via `Task.detached`, never inside a `body`, a `@MainActor .task`, or a `Reduce` closure.
- Stream large transfers. Use `URLSession.download`; never accumulate a response byte by byte with `URLSession.bytes`.
- Cancellation is not failure. In a view `.task`, guard `!Task.isCancelled` before committing any error, fallback or failed state. A cancelled load (tab switch, scroll away) must not flash an error.
- Split cancel IDs so unrelated effects do not cancel each other.

### Offline cache

- Stale-while-revalidate and fallback-only: paint the saved copy, then always refetch and overwrite. Fall back to cache only on an offline error, never on a real server error.
- **Security, non-negotiable:** every cache store is cleared on logout, session expiry and fresh sign-in. A saved list must never leak into the next account. Any new cache store must be wired into all clear sites.

## UI and design system

- Use DesignSystem components and tokens. Prefer a token over a local constant.
- **No magic numbers.** File or view specific constants belong in a `private enum Constants`. Share small constants across split files with a `private typealias Metrics = ...` alias or a per-file `private enum Constants` subset; do not duplicate a full metrics enum.
- Break up large views. A view file past roughly 400 lines is a monolith: extract rows, menus, sheets and section groups into their own standalone `struct`s, passing the store plus minimal inputs (not cross-file extensions, since Swift `private` is file-scoped).
- Each extracted view carries its own `#Preview`s covering every state: loading, loaded, empty, error, no-results.

## Localization

- Every user-facing string goes through `L10n.<key>`. No hard-coded display text.
- The app ships 30 languages. A new key is added to the string catalog for every language, with placeholder validation intact.
- Do not hand-edit the generated catalog. Edit the source and regenerate with the scripts below.

## Deterministic tests

A test gives the same result on every run, on every machine, under any load. CI enforces it with `Scripts/check-test-determinism.py`: any use of a banned pattern fails the build (there is no baseline or allow list).

| Instead of | Use |
|---|---|
| `Date()`, `Date.now`, a literal `Date(timeIntervalSince1970: N)` | `MockDate.date` from `TestUtils` (one fixed instant), plus offsets such as `MockDate.date.addingTimeInterval(600)`. A decode or format test whose expected instant must match fixture text may name an epoch, with a comment |
| `UUID()` | `UUID(0)`, `UUID(1)`, the `.incrementing` dependency, or `TestID.uuid()` / `TestID.name()` for unique names |
| `Task.sleep`, `Thread.sleep`, `clock.sleep`, a mock that sleeps | `AsyncGate` / `suspendUntilCancelled()` from `TestUtils`, opened by the test. Never sleep in a test. Production delays use the injected `continuousClock`, advanced with `TestClock`. Never a real clock: | inject `continuousClock`, drive a `TestClock` and `await clock.advance(by:)` (or `ImmediateClock`) |
| polling with a time budget, `XCTWaiter` | `await store.receive(...)`, `await store.finish()`, or await the task |
| `exhaustivity = .off`, `skipReceivedActions()` | assert every state change and receive every action |
| `Int.random`, `shuffled()` | a seeded generator |
| `URLSession.shared` | an injected client |

Also:

- Tests take milliseconds: nothing waits on real time, and a whole package runs in a few seconds.
- Unique temp folder names and store scopes come from `TestID.name()` / `TestID.uuid()` in `TestUtils`, never `UUID()`.
- Split large tests: keep a test file under about 600 lines, one suite per behavior area, shared fixtures in a support file. CI fails bigger files (existing ones can only shrink).
- Constants, not literals: Test data is a constant, never a retyped literal: a value used in 2+ files lives once in `TestUtils` (`TestFolder`, `TestFile`, `TestPath`, `TestKind`, `TestAccount`, `TestUser`, `TestHost`, `TestSession`, `TestStorageKey` ...), a value repeated inside one file is in that file's `private enum Constants`, and where production already has a typed constant or enum (`HTTPMethod`, `HTTPHeaderField`, `MIMEType`, `FileItem.directoryKind`) the test uses that. Only a wire value or decode input that IS the point of the test stays a literal.
- Share test data: names and credentials used by several tests live once in `TestUtils` (`TestFolder`, `TestFile`, `TestAccount`, `TestHost`). No inline JSON in a test (`Data("{...}".utf8)`, raw strings, interpolated payloads): JSON bodies are `.json` files under `Tests/<Target>/Fixtures/`, named by one `FixtureFile` enum per target with an audit test (see `CoreModelsFixture`).
- Expected values are literals, never computed from the code under test.
- Work that must overlap is held and released with explicit gates, never a timing window.
- Each test owns its state: a unique temporary directory or `UserDefaults` suite per test.
- A test that fails only on CI has a race. Fix the race. Do not add a retry or a longer timeout.
- UI tests in CI rerun a failed test once, on its own (`Scripts/ci-ui-tests.py`). A test that passes only on that rerun is flagged on the pull request as flaky: fix it like any other failure. UI tests run on `main`, from "Run workflow" on a branch, and on a pull request labelled `ui-tests` (from the next push after labelling).
- When you edit a test file, remove its existing uses of the patterns above in the same change.

## Scripts

Helpers under `Scripts/`. Two drive localization; the others keep dependency pins aligned and build release notes. The `Localization` package is generated, so localization changes flow through these, not by editing `Localizable.xcstrings` or `L10n.swift` directly.

- **`gen-l10n.py`** regenerates the `Localization` package from its human-edited source. `Packages/Localization/strings.tsv` (one `key<TAB>English` per line) is the source of truth; the script rewrites `Localizable.xcstrings` and the two-level `L10n.swift` accessors, folds in each `translations/<lang>.tsv`, falls back to English for missing keys, and re-checks placeholder integrity. Run it after any string change: `python3 Scripts/gen-l10n.py`.
- **`machine-translate.py`** fills `translations/<lang>.tsv` for the non-hand-authored languages via deep-translator's keyless MyMemory backend. Format specifiers (`%@`, `%lld`, `%1$@`, ...) are masked before translation and restored after, so none are dropped; per-string failures fall back to English. Its output is always re-validated by `gen-l10n.py`.
- **`sync-package-pins.py`** keeps every local package's `Package.resolved` (and the CI only `PackageTests.xcworkspace`) on the app's dependency versions, so a package's tests run against what ships. Run it after changing dependencies in Xcode; CI runs it with `--check` and fails on drift.
- **`ci-restore-mtimes.py`** sets every tracked file's modification time to its last commit's time. CI runs it after each checkout: Xcode recompiles by modification time, and a fresh checkout's clone time made the cached DerivedData recompile every package.
- **`gen-changelog.py`** builds release notes from the history of `main`: every PR lands as one commit, and each release is tagged `v<version>`, so PR titles group by the release they shipped in (history before the first tag groups by the `MARKETING_VERSION` it carried). Notes speak to users: a feature clause is listed as written, while clauses about fixes, audits, crashes, performance, tests, CI, tooling, refactors or docs fold into one closing "Bug fixes and improvements" line (a title that opens with a fix or an audit folds whole), and version numbers are dropped. So **write PR titles as what a user would notice**, one benefit per clause, and put fixes and internal work in their own clauses. `--notes <version>` prints one version's notes (TestFlight "What to Test", GitHub Release with `--links`); with no option it prints the whole changelog as Markdown.

## Naming and style

- Boolean properties begin with `is`, `are`, `has`, `can` or `should`.
- Match the naming and idiom of the surrounding code.
- Comments are minimal, and carry no hyphens or em dashes.

## Build and test before you push

- Build and run every change on the QA simulator: **iPhone 17 Pro, iOS 27**. Use it for builds, package tests and any visual QA pass.
- Run every package's tests, on the QA simulator and, for Mac changes, on the Mac, and make sure they pass:
  ```sh
  xcodebuild test -workspace PackageTests.xcworkspace -scheme PackageTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
  xcodebuild test -workspace PackageTests.xcworkspace -scheme PackageTests -destination 'platform=macOS'
  ```
  `bundle exec fastlane unit_tests` runs the first. The XCUITest suites run from the **NextExplorer** scheme (`fastlane ui_tests` on iOS; `-only-testing:NextExplorerUITests/MacCriticalPathUITests` with `-destination 'platform=macOS'` on the Mac, which drives the real pointer and keyboard).
- Lint as CI does (its Lint job gates `main`): `swiftformat . --lint` and `swiftlint`, with the versions CI pins (SwiftFormat 0.64.4, SwiftLint 0.65.1) and the repo's `.swiftformat` and `.swiftlint.yml`. Imports are sorted, so a new import goes in its alphabetical slot.
- Confirm strings are localized, there are no magic numbers, and the app builds cleanly for both iOS and the Mac before opening the PR.

## Releasing

Releases go out with [fastlane](https://fastlane.tools), pinned in the `Gemfile` (Ruby version in `.ruby-version`). Run `bundle install` once.

- Create an App Store Connect API key (Users and Access › Integrations, App Manager role) and keep the `.p8` outside the repo, e.g. `~/.appstoreconnect/private_keys/`.
- Put its details in `fastlane/.env` (git ignored): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`, and optionally `GH_USER` (the `gh` account used for the CI check and the GitHub Release).
- Once per Mac, for the Mac App Store package: an App Manager key can't create its certificate or profile. In Xcode, Settings › Accounts › Manage Certificates › **+** › Mac Installer Distribution; then archive the app for Any Mac and choose Distribute App › Custom › App Store Connect › **Export** (not Upload, which would spend a build number), which creates the Mac App Store profile.

Versions come from git tags. A release ships the next version after the newest `v<version>` tag (patch by default) by passing `MARKETING_VERSION` to the archive, then tags it. To plan a minor or major, set the project's `MARKETING_VERSION` ahead of the newest tag: a release without `bump:` or `version:` then ships that version. The build number is the git commit count, stamped at build time.

iPhone, iPad and Mac are one target and share one version: a release ships both apps from the same commit under one tag.

Lanes (`bundle exec fastlane <lane>`, `ios` is the default platform):

- `unit_tests`: every package's tests on the simulator, same set as CI. Option `device:"iPhone Duo"`.
- `ui_tests`: the XCUITest suite. Options `device:`, `only_testing:"SettingsUITests,SharedUITests"`.
- `beta`: the upcoming version's Release archive, uploaded to TestFlight.
- `release_dry_run`: tag check, unit tests, and the Release iPhone/iPad app and Mac package, nothing uploaded. Option `platforms:` as below.
- `release`: from a clean, up to date `main`. Refuses if the version is already tagged; skips the local unit tests when CI's Build and test already passed on that commit; cuts and pushes `release/<version>`; builds and uploads both apps and waits for processing; submits both for review and releases automatically once approved (`manual_release:true` holds it, `phased:true` rolls out over 7 days); tags `v<version>` and publishes a GitHub Release with the notes. Options `bump:` (`patch`, `minor`, `major`) or `version:`. Store text and screenshots stay in App Store Connect. `platforms:ios` or `platforms:mac` ships only that app (the other skips the version). The Mac's first version (1.1.0) goes out without What's New.

Uploads carry the version's `gen-changelog.py` notes as TestFlight's "What to Test" and go to the "External Testers" group (override with `TESTFLIGHT_GROUPS`); the internal group receives every build on its own, and App Store Connect refuses to assign one to it.

Mac only lanes (`bundle exec fastlane mac <lane>`):

- `unit_tests`: every package's tests on the Mac.
- `ui_tests`: the Mac XCUITest suite (`MacCriticalPathUITests`). It drives the real app, so leave the Mac alone while it runs.
- `beta`: the upcoming version as a Mac App Store package, uploaded to TestFlight for macOS.
- `release_dry_run`: Mac unit tests and the Mac App Store package, nothing uploaded.

The Mac app shares the iOS app's App Store record (same bundle ID, a universal purchase, so the tip jar carries over); it first shipped with 1.1.0. Its package is signed with a Mac Installer Distribution certificate; on a new release Mac, create it once as described above.

## Questions

Open an issue or reach out through the [support site](https://phillipmaizza.com/nextexplorer). Happy to help you get oriented.
