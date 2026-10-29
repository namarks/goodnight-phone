# Goodnight Phone

Personal iOS app: blocks chosen apps while the iPhone is in the bedroom (iBeacon in range) during bedtime hours. See README.md for the user-facing setup and architecture table.

## Build

- The Xcode project is **generated** by XcodeGen from `project.yml`. Never edit `GoodnightPhone.xcodeproj` (it's gitignored). After changing `project.yml` or adding/removing files, regenerate.
- First-time / regenerate (non-interactive):
  `TEAM_ID=<10-char team id> BUNDLE_PREFIX=<com.something> ./setup.sh`
  Answers are cached in `.goodnightphone.env` (gitignored), so later runs are just `./setup.sh`. It finishes with `open GoodnightPhone.xcodeproj`.
- Compile check without a device:
  `xcodebuild -project GoodnightPhone.xcodeproj -scheme GoodnightPhone -destination 'generic/platform=iOS' -allowProvisioningUpdates build | xcbeautify` (fall back to `| tail -50` if xcbeautify isn't installed)
- Screen Time APIs (FamilyControls, ManagedSettings, DeviceActivity) and beacon monitoring don't work in the Simulator; real behavior needs a device.

## Layout

- `Shared/` is compiled into both the app and the Monitor extension. Shared state lives in App Group UserDefaults (`Shared` enum). The App Group ID comes from the `GoodnightPhoneAppGroup` Info.plist key that project.yml injects.
- `Blocker.refresh(reason:)` is the single decision point ((in room AND bedtime hours, OR a `TestBlock` running) AND selection non-empty). `Shared/TestBlock.swift` is the 2-minute "Try it now" block for new users and App Review; it only adds a block and can't be cancelled. It's idempotent; call it whenever an input changes.
- `App/RoomMonitor.swift`: CLMonitor + BeaconIdentityCondition, started on every launch from AppDelegate (required for background relaunch delivery). `RoomMonitor.setInRoom` is the only writer of `Shared.inRoom`.
- Two detection modes, picked by `Shared.beacon`: a real iBeacon (RoomMonitor/CLMonitor, binary in/out), or `BeaconConfig.standIn` (`isStandIn`), a spare iPad/iPhone watched by `App/HubMonitor.swift` over a CoreBluetooth connection. HubMonitor uses `bluetooth-central` background mode + state restoration, reads RSSI on each heartbeat notification (plus a 1 s poll while the app is in the foreground), and feeds them to `RoomPresenceStateMachine` (`App/Presence/RoomPresence.swift`, pure and unit-tested in `Tests/`): median of the last 5 readings, enter at `Shared.hubBoundary` (calibrated at the bedroom door) +3 dB held 6 s, leave at boundary −5 dB held 20 s, 30 s with no readings = outside. Can't hear the spare device (disconnected, service withdrawn, Bluetooth off) = outside. No boundary = never in the room. `Blocker` reads `Shared.isInRoom(at:)`, which ignores a stand-in "in the bedroom" not confirmed in the last 60 s (`Shared.hubLastHeard`), so a force-quit can't leave you blocked elsewhere; HubMonitor re-runs `Blocker` when a stale one is confirmed.
- `App/BeaconBroadcaster.swift`: the spare device's side (CBPeripheralManager GATT service: notify heartbeat every 2 s, plus a writable characteristic where each phone writes its `PhoneHours` (schedule + time zone identifier, evaluated in the phone's zone); beats go only to phones inside their hours, with one pause value when hours end). Foreground only: it withdraws the service when the app leaves the screen so phones don't freeze on a stale reading, and the app keeps the screen awake while it's on.
- `App/BeaconSignal.swift`: foreground-only beacon ranging for the iBeacon Signal row. Display only; never feeds `Shared.inRoom`.
- `Extensions/Monitor`: DeviceActivityMonitor, which only calls `Blocker.refresh`. `Extensions/Shield` and `Extensions/ShieldAction`: custom blocked screen and its Close button.

## Conventions

- iOS 17+, Swift 5 language mode, strict concurrency minimal. UI and RoomMonitor are `@MainActor`.
- Every target that touches ManagedSettings needs the `com.apple.developer.family-controls` entitlement (already in project.yml).
- No "unlock anyway" path anywhere. Settings are locked while blocking, by design.
