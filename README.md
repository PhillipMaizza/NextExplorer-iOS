# NextExplorer for iOS

A fast, private, native file browser for your own self-hosted NextExplorer server.

Browse, preview, search and share every file on your server from a clean, native iOS app. You bring the server; NextExplorer brings the browsing. Your files, credentials and activity stay between your device and the server you choose, and nowhere else.

> **Your server, your rules.** NextExplorer for iOS is a *client*. You supply the address of your own compatible file server and sign in with your own credentials. There is no NextExplorer account, no middleman, and no tracking.

---

## Screenshots

Raw captures from an iPhone. No mockups, no marketing frames, this is the actual app.

| Browse | Search | Favorites | Shared | Settings |
|:---:|:---:|:---:|:---:|:---:|
| <img src="Screenshots/browse.png" width="180" alt="Browsing folders and files"> | <img src="Screenshots/search.png" width="180" alt="Searching by name and full text"> | <img src="Screenshots/favorites.png" width="180" alt="Starred favorites"> | <img src="Screenshots/shared.png" width="180" alt="Shared by me and with me"> | <img src="Screenshots/settings.png" width="180" alt="Settings"> |

---

## Features

- **Browse & preview.** Folders, documents, photos, video, code and archives in one clean library, with rich previews and a swipeable media gallery. Non-native media (avi, mkv, webm and more) plays through a built-in VLC-backed player.
- **Find it fast.** Search by name or full text across every folder, then filter by type to jump straight to what you need.
- **Favorites & sharing.** Star what you reach for, share files by link, and see what others shared with you, all in one place.
- **Sign in your way.** Username and password, or single sign-on and passkeys through your own identity provider.
- **Works offline.** A saved-copy view keeps your recent folders readable when the connection drops, then refreshes when you are back.
- **Everyone's app.** 17 languages with full right-to-left support, plus complete VoiceOver and Dynamic Type accessibility.
- **iPhone and iPad.** Universal layout with a split-view sidebar on larger screens.

---

## Requirements

- iOS 18 or later
- iPhone or iPad
- A compatible self-hosted NextExplorer server and your own account on it

---

## Building from source

1. Install Xcode 16 or later.
2. Clone the repo:
   ```sh
   git clone git@github.com:PhillipMaizza/NextExplorer-iOS.git
   cd NextExplorer-iOS
   ```
3. Open `NextExplorer.xcodeproj` in Xcode.
4. Select the **NextExplorer** scheme and an iOS 18+ simulator or device, then Run.

Swift Package Manager resolves all dependencies on first build; there is nothing to install by hand. To run the tests, use `Product > Test` in Xcode, or `xcodebuild test` against a matching simulator.

---

## Architecture

Native iOS, SwiftUI, and [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). The app is split into focused Swift packages under `Packages/`:

| Package | Responsibility |
|---|---|
| `AppFeature` | App root, tab and window composition, session lifecycle |
| `AuthFeature` / `AuthClient` | Login, SSO, passkeys, session state |
| `FilesFeature` / `FilesClient` | Browse, preview, search, favorites, sharing, offline cache |
| `NetworkClient` | HTTP layer, ETag revalidation, connectivity |
| `CoreModels` | Shared domain models |
| `DesignSystem` | Colors, typography, reusable components |
| `Localization` | 17-language string catalog and live language switch |
| `Keychain` / `AppStorageKeys` | Credential storage and device preferences |

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the working conventions and [`CLAUDE.md`](CLAUDE.md) for the full architectural rules.

---

## Privacy

The app talks only to the server you point it at. It ships no analytics, no third-party trackers, and no telemetry. Cached copies of your data are cleared on logout, session expiry and fresh sign-in, so one account's files never leak into the next.

See the [Privacy Policy](https://nextexplorer.phillipmaizza.com) and [Terms of Use](https://nextexplorer.phillipmaizza.com) for the full text.

---

## Support

Questions, a bug, or a feature idea? Open an issue on this repo, or reach out through the [support site](https://nextexplorer.phillipmaizza.com). Replies usually land within a couple of days.

---

## License

Copyright © Phillip Maizza. All rights reserved. This source is published for review and reference; it is not currently offered under an open-source license. If you would like to reuse part of it, get in touch.
