# Repository Guidelines

## Project Structure & Module Organization
The app target lives in `DronePass/` with SwiftUI entry points such as `DronePassApp.swift`, `MainView.swift`, and tab containers. Feature folders (`Core`, `Shape`, `Login`, `Setting`, `Web`) package UI plus view models, while reusable services stay in `Manager/` (`AuthManager`, `RealtimeSyncManager`, `LocationManager`). `Model/` hosts DTOs, `Modifier/` wraps SwiftUI helpers, `Localization/` stores copy updates, and `Assets.xcassets` holds imagery. Keep `Info.plist`, `DronePass.entitlements`, and `GoogleService-Info.plist` aligned with their Apple and Firebase counterparts before releasing.

## Build, Test, and Development Commands
- `xcodebuild -scheme DronePass -configuration Debug build` — Headless build equivalent to ⌘B.
- `xcodebuild test -scheme DronePass -destination "platform=iOS Simulator,name=iPhone 15"` — Runs unit/UI targets; swap the device to whatever QA standardizes on.
- `xcodebuild clean` — Clears DerivedData when provisioning or SPM caches glitch.
- Xcode Run (⌘R) is the daily loop; ensure the bundled GoogleService plist targets your dev Firebase app before launch.

## Coding Style & Naming Conventions
Follow Swift 5.10 defaults with four-space indentation, `camelCase` members, and descriptive types (`ShapeRealtimeObserver`, `ChangeDetectionManager`). Favor SwiftUI-first code, bridging into UIKit only when SDKs such as NMapsMap demand hosted views. Shared state should leverage the `@Observable` macro or actors as already seen in `Manager/`. Keep files near 400 lines by splitting extensions and suffixing SwiftUI views with their feature (`LoginView`, `WeatherPanelView`).

## Testing Guidelines
No XCTest bundle ships yet; scaffold `DronePassTests` and `DronePassUITests` with methods named `testFeature_scenario_expectedResult`. Prioritize deterministic coverage for authentication, realtime sync, and geometry math by mocking Firebase services and supplying offline map fixtures. Run the `xcodebuild test` command above on the latest simulator before each PR and attach crash or console logs for any Firebase/Auth regressions.

## Commit & Pull Request Guidelines
Recent history favors short imperative Korean subjects (e.g., `앱 전역 알림기능 추가`). Match that voice or provide an equally concise English command under ~60 characters. Each PR should describe user impact, list core folders touched, link issues, and attach screenshots or recordings for UI work. Always highlight Info.plist, entitlement, or Firebase edits so reviewers can reproduce the configuration.

## Security & Configuration Tips
Never commit live API keys; keep secrets inside untracked xcconfigs or CI variables. When editing `GoogleService-Info.plist`, `Info.plist`, or `DronePass.entitlements`, confirm the bundle identifier and capabilities match the Apple Developer and Firebase projects. Ensure the Naver Map client ID in `Info.plist` aligns with the signed bundle to avoid runtime crashes.
