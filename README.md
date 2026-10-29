# Lights Out

A personal Brick Night: your chosen apps lock automatically when your iPhone is in the bedroom during bedtime hours, and unlock when you leave. No tapping, no buttons. Leaving the room is the off switch.

## What you need

- A Mac with Xcode and a **paid** Apple Developer account ($99/year). Free accounts (Personal Team) generally can't sign the Family Controls capability this needs.
- An iPhone on iOS 17 or later.
- **An iBeacon with adjustable transmit power**, roughly $15–25 (Blue Charm, Minew and Kontakt.io all sell them). You'll need its UUID, which is on the box or in the vendor's app. An ESP32 board broadcasting iBeacon over USB power also works. To test before it arrives, a spare iPad or iPhone can stand in (see [No beacon yet?](#no-beacon-yet)).

## Setup (about 10 minutes)

1. `./setup.sh` installs XcodeGen if needed, asks for your Team ID (it tries to detect it) and a bundle prefix, then generates and opens `LightsOut.xcodeproj`.
2. Plug in your iPhone, choose it as the run destination, and press **⌘R**. If this is the first time, turn on Settings → Privacy & Security → **Developer Mode**.
3. Work through the checklist in the app:
   - **Screen Time access**: Allow.
   - **Location**: Allow, then choose **Change to Always Allow**. Keep **Precise Location** on, because beacons don't work without it.
   - **Apps to block**: pick Instagram and anything else.
   - **Bedroom beacon**: paste the beacon's UUID.
4. To see it work before the beacon is set up, tap **Try it now → Block these apps for 2 minutes**, then open a blocked app. Like the real thing, the test can't be cancelled.
5. Set your bedtime hours (default 9 PM – 7 AM) or turn them off to block any time you're in the room.

## Tuning the beacon (the part that makes it feel right)

Bluetooth goes through walls, so out of the box the zone may reach the hallway.

1. Put the beacon on the far side of the nightstand, away from the door.
2. In the vendor's app, lower **transmit power** (try about −12 dBm or lower) and set the advertising interval to around 500 ms.
3. Walk out of the room and wait about 30 seconds. iOS waits a bit before deciding you've left. The app's Activity list should show "Left bedroom".
4. If it doesn't, lower the power one more step and try again. While Lights Out is open, the **Signal** row under Bedroom beacon shows live signal strength (RSSI) and a rough distance, so you can watch it drop as you walk to the door.

## How it works

```
Beacon in range ──► CLMonitor wakes the app (even when it's closed) ──┐
                                                                       ├─► Blocker: in room AND bedtime hours?
Bedtime starts/ends ──► DeviceActivity wakes the Monitor extension ───┘        │
                                                                        shield on / shield off
                                                                       (ManagedSettingsStore)
```

| Path | What it does |
|---|---|
| `Shared/Blocker.swift` | The single decision: blocks when you're in the room, it's bedtime and apps are selected; clears the shield otherwise. Safe to call any time. |
| `Shared/SharedState.swift` | App Group storage shared by the app and the Monitor extension: selection, schedule, beacon, in-room flag, activity log. |
| `Shared/BedtimeActivities.swift` | Registers short DeviceActivity windows at the start and end of bedtime to wake the extension. iOS delivers these while the phone is in use, so if it's asleep on the nightstand at 9 PM, blocking turns on the next time you pick it up. |
| `App/RoomMonitor.swift` | Watches the beacon with `CLMonitor`, and on iOS 18+ holds a `CLServiceSession` once "Always" is granted. It's started on every launch, which is how iOS delivers enter/exit events in the background. |
| `App/ContentView.swift` | Status card, setup checklist, apps, hours, beacon, activity log. |
| `App/BeaconSignal.swift` | The live Signal row: ranges the beacon while the app is open. Display only; blocking follows `RoomMonitor`. |
| `App/BeaconBroadcaster.swift` | Stand-in mode: broadcasts a fixed iBeacon UUID from a spare iPad or iPhone. |
| `Extensions/Monitor` | `DeviceActivityMonitor` that calls `Blocker` at bedtime boundaries. |
| `Extensions/Shield` | The custom "Not in the bedroom" screen. |
| `Extensions/ShieldAction` | The shield's only button, Close. There's no "unlock anyway". |

While apps are blocked, the app's settings are locked too. To change them, leave the room.

## Escape hatch

Like Brick, this isn't airtight on purpose. For a real emergency, go to Settings → Screen Time → Apps with Screen Time Access and turn **Lights Out** off; that removes every block. Opening the app also re-checks the beacon, so a missed "left the room" event fixes itself.

## Adding your partner's phone

Plug their iPhone into the Mac once so Xcode registers it with your team, then press ⌘R with their phone selected. Both phones watch the same beacon, and each person picks their own apps and hours on their own phone.

## No beacon yet?

A spare iPad or iPhone can stand in while you test:

1. Install Lights Out on the spare device the same way (plug it in, pick it as the run destination, ⌘R). It doesn't need the setup checklist.
2. On the spare device, open **No beacon yet? → Broadcast as bedroom beacon**, turn it on and allow Bluetooth. Leave Lights Out open (any screen), plugged in, by the bed. iOS only broadcasts while the app is on screen, so the display stays on.
3. On your iPhone, tap **Add beacon…** (or **Change beacon…**), then **Use a spare iPad or iPhone**, then **Save**.

A phone or iPad can't turn its signal down like a real beacon, so the "bedroom" may reach past the door. Use it to check that blocking works, then switch to a real beacon.

## Troubleshooting

- **Signing error about Family Controls or App Groups.** Select each target, open **Signing & Capabilities**, and make sure your team is selected. Xcode registers the capabilities automatically. If one shows an error, click "Try Again".
- **Shield never appears.** All three extensions need the Family Controls capability, and `project.yml` already sets it. Check that Screen Time access shows as allowed in the app.
- **"Couldn't schedule bedtime hours" in Activity.** Screen Time access was revoked. Allow it again from the setup checklist.
- **Walking in doesn't block anything, but the app shows "In range" once opened.** Background delivery isn't working. Check that Location is set to Always with Precise on, and that Background App Refresh is on for Lights Out.
- **Only your own phones.** Development builds are fine for that. Shipping through TestFlight or the App Store requires Apple to approve the Family Controls (Distribution) entitlement separately.

Re-run `./setup.sh` after editing `project.yml`. The `.xcodeproj` is generated, so don't edit it by hand.
