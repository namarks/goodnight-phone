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
- `Shared/BedtimeSchedule.swift`: usual start/end plus `nights` (7, Sunday first): `.usual`, `.hours(start:end:)` or `.off`. A night belongs to the weekday it starts on, so `contains` checks tonight and whether last night is still running. Pure and unit-tested. `BedtimeActivities` registers one daily wake window per distinct boundary time (`boundaries`), and Blocker reads the weekday itself.
- `Blocker.refresh(reason:)` is the single decision point ((in room AND bedtime hours, OR a `TestBlock` running) AND selection non-empty). `Shared/TestBlock.swift` is the 2-minute "Try it now" block for new users and App Review; it only adds a block; `TestBlock.stop()` ends it early (never lifts a real block). It's idempotent; call it whenever an input changes. iOS shields at most 50 apps/sites per ManagedSettingsStore, so Blocker splits them across named stores `bedroom`, `bedroom2`… (`maxStores`), categories in the first; it clears every store when blocking stops.
- `App/RoomMonitor.swift`: CLMonitor + BeaconIdentityCondition, started on every launch from AppDelegate (required for background relaunch delivery). `RoomMonitor.setInRoom` is the only writer of `Shared.inRoom`.
- Two detection modes, picked by `Shared.beacon`: a real iBeacon (RoomMonitor/CLMonitor, binary in/out), or `BeaconConfig.standIn` (`isStandIn`), a spare iPad/iPhone watched by `App/HubMonitor.swift` over a CoreBluetooth connection. HubMonitor uses `bluetooth-central` background mode + state restoration, reads RSSI on each heartbeat notification (plus a 1 s poll while the app is in the foreground), and feeds them to `RoomPresenceStateMachine` (`App/Presence/RoomPresence.swift`, pure and unit-tested in `Tests/`): median of the last 5 readings, enter at `Shared.hubBoundary` (calibrated at the bedroom door) +3 dB held 6 s, leave at boundary −5 dB held 10 s, 30 s with no readings = outside. Can't hear the spare device (disconnected, service withdrawn, Bluetooth off) = outside. No boundary = never in the room. `Blocker` reads `Shared.isInRoom(at:)`, which ignores a stand-in "in the bedroom" not confirmed in the last 60 s (`Shared.hubLastHeard`), so a force-quit can't leave you blocked elsewhere; HubMonitor re-runs `Blocker` when a stale one is confirmed.
- `App/BeaconBroadcaster.swift`: the spare device's side (CBPeripheralManager GATT service: notify heartbeat every 2 s, plus a writable characteristic where each phone writes its `PhoneHours` (schedule + time zone identifier, evaluated in the phone's zone); beats go only to phones inside their hours, with one pause value when hours end). Foreground only: it withdraws the service when the app leaves the screen so phones don't freeze on a stale reading, and the app keeps the screen awake while it's on.
- `App/BlueCharm.swift`: in-app setup and range (TX power steps) for the recommended Blue Charm beacons (USB BC-U1, coin-cell BC05; both KKM firmware), through KKM's kbeaconlib2 SDK, vendored unmodified in `Vendor/kbeaconlib2` and built as its own framework target. Writes a fresh UUID at -20 dBm; `Shared.blueCharm` remembers the pairing (counts only while its UUID is still `Shared.beacon`). Range buttons are disabled while locked, except for 15 minutes after setup (`BlueCharmPairing.tuningWindow`), since setup usually happens in the bedroom at bedtime. While the app is open, `watchSignal` scans for the paired beacon's own Bluetooth advertising to drive the Signal row (iOS beacon ranging showed "Not detected" even while CLMonitor heard the beacon). It never writes `Shared.inRoom` itself, but if that scan hears nothing for 60 s while Status says in the room, `checkRoom` asks `RoomMonitor.recheck()` to re-add the CLMonitor condition from "outside" (CLMonitor once stayed satisfied 15+ min with the beacon unplugged); one recheck per stretch of silence.
- `App/BeaconSignal.swift`: foreground-only beacon ranging for the iBeacon Signal row. Display only; never feeds `Shared.inRoom`.
- `App/Brand.swift`: the picture-book look (nursery green, blanket red, moon yellow, night blue on paper; colors are colorsets in `App/Assets.xcassets` with dark variants; heading font Fraunces Soft, a static cut bundled in `App/Fonts` via `UIAppFonts`). Forms use `.brandForm()` and each Section `.brandRow()`. The illustrations (icon, onboarding scenes, shield icon) are original art; never copy Goodnight Moon's illustrations, characters or wording.
- `App/BeaconPlacementGuide.swift`: "Where to put the beacon", illustrated tips for placing it where unplugging takes effort. Read-only, so it stays open while blocking. Linked from the Bedroom beacon section and the beacon editor. Its scenes (`Guide*` imagesets) are rendered from `docs/art/guide-scenes.py` (SVG, then Playwright at 3x).
- `Extensions/Monitor`: DeviceActivityMonitor, which only calls `Blocker.refresh`. `Extensions/Shield` and `Extensions/ShieldAction`: custom blocked screen and its Close button.

## Conventions

- iOS 17+, Swift 5 language mode, strict concurrency minimal. UI and RoomMonitor are `@MainActor`.
- Every target that touches ManagedSettings needs the `com.apple.developer.family-controls` entitlement (already in project.yml).
- No "unlock anyway" path anywhere. Settings are locked while blocking, by design.
