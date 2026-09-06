# Repository Guidelines

## Project Structure & Module Organization
The app target lives in `DronePass/` with SwiftUI entry points such as `DronePassApp.swift`, `MainView.swift`, and tab containers. Feature folders (`Core`, `Shape`, `Login`, `Setting`, `Web`) package UI plus view models, while reusable services stay in `Manager/` (`AuthManager`, `RealtimeSyncManager`, `LocationManager`). `Model/` hosts DTOs, `Modifier/` wraps SwiftUI helpers, `Localization/` stores copy updates, and `Assets.xcassets` holds imagery. `Info.plist`, `DronePass.entitlements`, and `GoogleService-Info.plist` ship in the repo as-is; use them unchanged. `Info.plist` holds `$(...)` placeholders that the build substitutes from `DronePass/Config/Secrets.xcconfig` (gitignored) — never write a key value into the plist.

## Build, Test, and Development Commands
- `xcodebuild -scheme DronePass -configuration Debug build` — Headless build equivalent to ⌘B.
- `xcodebuild test -scheme DronePass -destination "platform=iOS Simulator,name=iPhone 16"` — Runs the `DronePassTests` target; swap the device for any simulator on iOS 17.6 or newer.
- `xcodebuild clean` — Clears DerivedData when provisioning or SPM caches glitch.
- Xcode Run (⌘R) is the daily loop. Use the bundled `GoogleService-Info.plist` as committed. If you want to point the app at your own Firebase project, swap the file **locally only and never commit the swap** — committing it would publish someone else's Firebase configuration.

## Coding Style & Naming Conventions
Follow the project's Swift 5.0 language mode (`SWIFT_VERSION = 5.0`) with four-space indentation, `camelCase` members, and descriptive types (`ShapeRealtimeObserver`, `ChangeDetectionManager`). Favor SwiftUI-first code, bridging into UIKit only when SDKs such as NMapsMap demand hosted views. Shared state should leverage the `@Observable` macro or actors as already seen in `Manager/`. Keep files near 400 lines by splitting extensions and suffixing SwiftUI views with their feature (`LoginView`, `WeatherPanelView`).

## Testing Guidelines
`DronePassTests/` ships two XCTest suites:

- `CrossPlatformFirestoreContractTests.swift` — the important one. It loads `team/fixtures/*.json` and asserts that `ShapeFirebaseStore`'s read/write mapping matches the contract in `team/DATA_CONTRACT.md`, which the Android app's mirror test checks against the same fixtures. It calls `Firestore.disableNetwork()` in `setUp` so it never touches production data. **If you change the shape of anything DronePass reads from or writes to Firestore, update `ShapeFirebaseStore`, `team/DATA_CONTRACT.md`, and the fixtures in `team/fixtures/` in the same change, and keep this test passing** — otherwise iOS and Android silently drift apart on the same documents.
- `UserActivityTrackingTests.swift` — pure unit tests for the `shouldRecordUserActivity` throttle window.

New tests go in the same bundle with methods named `testFeature_scenario_expectedResult`. Prioritize deterministic coverage for authentication, realtime sync, and geometry math by mocking Firebase services and supplying offline map fixtures. Run the `xcodebuild test` command above before each PR and attach crash or console logs for any Firebase/Auth regressions.

## Commit & Pull Request Guidelines
Use short imperative Korean subjects (e.g., `앱 전역 알림기능 추가`) or an equally concise English command under ~60 characters. Each PR should describe user impact, list core folders touched, link issues, and attach screenshots or recordings for UI work. Always call out Info.plist, entitlement, or Firebase edits so the configuration change is reproducible.

## Security & Configuration Tips
Never commit live API keys. Naver and VWorld keys live only in `DronePass/Config/Secrets.xcconfig` (gitignored, copied from `Secrets.xcconfig.example`); `Info.plist` carries `$(...)` placeholders the build substitutes, so the keys never reach source control. `GoogleService-Info.plist` is committed on purpose — it is a Firebase client identifier, not a secret, and access control lives in the Firestore and Storage security rules; a Firebase service-account key must never enter this repo. When touching `Info.plist` or `DronePass.entitlements`, confirm the bundle identifier and capabilities still match the Apple Developer and Firebase projects.
