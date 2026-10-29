# Lights Out

Personal iOS app: blocks chosen apps while the iPhone is in the bedroom (iBeacon in range) during bedtime hours. See README.md for the user-facing setup and architecture table.

## Build

- The Xcode project is **generated** by XcodeGen from `project.yml`. Never edit `LightsOut.xcodeproj` (it's gitignored). After changing `project.yml` or adding/removing files, regenerate.
- First-time / regenerate (non-interactive):
  `TEAM_ID=<10-char team id> BUNDLE_PREFIX=<com.something> ./setup.sh`
  Answers are cached in `.lightsout.env` (gitignored), so later runs are just `./setup.sh`. It finishes with `open LightsOut.xcodeproj`.
- Compile check without a device:
  `xcodebuild -project LightsOut.xcodeproj -scheme LightsOut -destination 'generic/platform=iOS' -allowProvisioningUpdates build | xcbeautify` (fall back to `| tail -50` if xcbeautify isn't installed)
- Screen Time APIs (FamilyControls, ManagedSettings, DeviceActivity) and beacon monitoring don't work in the Simulator; real behavior needs a device.

## Layout

- `Shared/` is compiled into both the app and the Monitor extension. Shared state lives in App Group UserDefaults (`Shared` enum). The App Group ID comes from the `LightsOutAppGroup` Info.plist key that project.yml injects.
- `Blocker.refresh(reason:)` is the single decision point (in room AND bedtime hours AND selection non-empty). It's idempotent; call it whenever an input changes.
- `App/RoomMonitor.swift`: CLMonitor + BeaconIdentityCondition, started on every launch from AppDelegate (required for background relaunch delivery).
- `App/BeaconSignal.swift`: foreground-only beacon ranging for the live Signal row. Display only; never feeds `Shared.inRoom`.
- `App/BeaconBroadcaster.swift`: stand-in mode for testing without a beacon. `BeaconBroadcaster.shared` broadcasts the fixed `BeaconConfig.standInUUID` on any screen while the app is in the foreground (iOS drops iBeacon data in the background).
- `Extensions/Monitor`: DeviceActivityMonitor, which only calls `Blocker.refresh`. `Extensions/Shield` and `Extensions/ShieldAction`: custom blocked screen and its Close button.

## Conventions

- iOS 17+, Swift 5 language mode, strict concurrency minimal. UI and RoomMonitor are `@MainActor`.
- Every target that touches ManagedSettings needs the `com.apple.developer.family-controls` entitlement (already in project.yml).
- No "unlock anyway" path anywhere. Settings are locked while blocking, by design.
