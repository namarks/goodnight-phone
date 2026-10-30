# Goodnight Phone

A personal Brick Night: your chosen apps lock automatically when your iPhone is in the bedroom during bedtime hours, and unlock when you leave. No tapping, no buttons. Leaving the room is the off switch.

## What you need

- A Mac with Xcode and a **paid** Apple Developer account ($99/year). Free accounts (Personal Team) generally can't sign the Family Controls capability this needs.
- An iPhone on iOS 17 or later.
- **An iBeacon with adjustable transmit power**, roughly $15–25. We recommend the [Blue Charm BC-U1](https://www.amazon.com/dp/B09FYNK94F) (about $19): it runs off any USB-A charger, so there's no battery to die and quietly end blocking, and its power goes down to −40 dBm. Goodnight Phone sets it up itself, no other app needed: it gives the beacon an ID of its own and lets you shorten or lengthen its range from the app. Any other iBeacon works too (Minew and Kontakt.io sell them); you'll need its UUID, which is on the box or in the vendor's app, and you tune its range in the vendor's app. An ESP32 board broadcasting iBeacon over USB power also works; [`hardware/esp32-ibeacon.yaml`](hardware/esp32-ibeacon.yaml) is a ready ESPHome config (tested on a Seeed XIAO ESP32-C6). To test before it arrives, a spare iPad or iPhone can stand in (see [No beacon yet?](#no-beacon-yet)).

## Setup (about 10 minutes)

1. `./setup.sh` installs XcodeGen if needed, asks for your Team ID (it tries to detect it) and a bundle prefix, then generates and opens `GoodnightPhone.xcodeproj`.
2. Plug in your iPhone, choose it as the run destination, and press **⌘R**. If this is the first time, turn on Settings → Privacy & Security → **Developer Mode**.
3. Work through the checklist in the app:
   - **Screen Time access**: Allow.
   - **Location**: Allow, then choose **Change to Always Allow**. Keep **Precise Location** on, because beacons don't work without it.
   - **Apps to block**: pick Instagram and anything else.
   - **Bedroom beacon**: with a Blue Charm, plug it in, hold your iPhone next to it and tap **Set up Blue Charm beacon**. With another beacon, paste its UUID.
4. To see it work before the beacon is set up, tap **Try it now → Block these apps for 2 minutes**, then open a blocked app. Like the real thing, the test can't be cancelled.
5. Set your bedtime hours (default 9 PM – 7 AM) or turn them off to block any time you're in the room. Tap a day's circle to take that night off (say, Friday and Saturday), and use **Hours by night** to give a night its own hours. A night belongs to the day it starts: Friday night runs from Friday evening into Saturday morning.

## Tuning the beacon (the part that makes it feel right)

Bluetooth goes through walls, so out of the box the zone may reach the hallway.

1. Put the beacon on the far side of the nightstand, away from the door.
2. With a Blue Charm set up from the app, use **Shorter** and **Longer** under Bedroom beacon instead of steps 2–4: it starts at −12 dBm, and each tap moves one power step (changes are locked while apps are blocked). With another beacon, in the vendor's app, lower **transmit power** (try about −12 dBm or lower) and set the advertising interval to around 500 ms.
3. Walk out of the room and wait about 30 seconds. iOS waits a bit before deciding you've left. The app's Activity list should show "Left bedroom".
4. If it doesn't, lower the power one more step and try again. While Goodnight Phone is open, the **Signal** row under Bedroom beacon shows live signal strength (RSSI) and a rough distance, so you can watch it drop as you walk to the door.

## Battery

**With a real beacon, Goodnight Phone costs almost nothing.** It uses iOS region monitoring (`CLMonitor`): you hand iOS the beacon's UUID, and the phone's Bluetooth chip listens for it in hardware alongside everything else it's already doing. Goodnight Phone isn't running and isn't scanning. iOS wakes it only when you cross into or out of range, a few times a night, for a fraction of a second each. So yes, the phone effectively only "looks" when it's near the beacon.

The one exception is the live **Signal** row: while Goodnight Phone is open on screen it ranges the beacon about once a second, and that stops the moment you leave the app. It's display only, and never runs in the background.

**With a spare iPad or iPhone (hub mode), it costs more, but only at night.** iOS can't watch a signal-strength boundary in hardware, so your phone stays connected to the spare device and checks the signal on each heartbeat. Your phone tells the spare device your bedtime hours, and it only sends heartbeats during them, every 2 seconds. Outside bedtime the connection stays open but silent, which costs about the same as being paired with AirPods you aren't using. It's a modest cost, and it falls when the phone is usually on its charger. A real beacon removes even that. If bedtime hours are off ("Any time"), the heartbeat runs all day. (While Goodnight Phone is open on screen it also reads the signal every second, for the Signal row and setting the boundary.)

Why the spare device decides when to talk, not your phone: iOS gives a closed app no reliable way to wake itself at 9 PM, so the heartbeat has to start from the spare device's side.

## How it works

```
Beacon in range ──► CLMonitor wakes the app (even when it's closed) ──┐
  or                                                                   │
Spare-device heartbeat ──► HubMonitor: signal vs. your door boundary ──┼─► Blocker: in room AND bedtime hours?
                                                                       │          │
Bedtime starts/ends ──► DeviceActivity wakes the Monitor extension ───┘   shield on / shield off
                                                                          (ManagedSettingsStore)
```

| Path | What it does |
|---|---|
| `Shared/Blocker.swift` | The single decision: blocks when you're in the room, it's bedtime and apps are selected; clears the shield otherwise. Safe to call any time. |
| `Shared/SharedState.swift` | App Group storage shared by the app and the Monitor extension: selection, schedule, beacon, in-room flag, activity log. |
| `Shared/BedtimeSchedule.swift` | Bedtime hours: usual hours, plus per-night hours or nights off. Unit-tested in `Tests/`. |
| `Shared/BedtimeActivities.swift` | Registers a short daily DeviceActivity window at every start and end time across the week to wake the extension. iOS delivers these while the phone is in use, so if it's asleep on the nightstand at 9 PM, blocking turns on the next time you pick it up. |
| `App/RoomMonitor.swift` | Watches the beacon with `CLMonitor`, and on iOS 18+ holds a `CLServiceSession` once "Always" is granted. It's started on every launch, which is how iOS delivers enter/exit events in the background. |
| `App/ContentView.swift` | Status card, setup checklist, apps, hours, beacon, activity log. |
| `App/HubMonitor.swift` | With a spare iPad or iPhone as the beacon: stays connected to it over Bluetooth (also with the app closed), reads the signal on each heartbeat, and decides in or out against the boundary you set at the bedroom door. |
| `App/BlueCharm.swift` | Sets up the recommended Blue Charm beacon over Bluetooth (its own UUID, starting power) and changes its range, using KKM's SDK vendored in `Vendor/kbeaconlib2`. Only during setup or a range change; blocking never depends on it. |
| `App/BeaconSignal.swift` | The live Signal row for a real iBeacon: ranges the beacon while the app is open. Display only; blocking follows `RoomMonitor`. |
| `App/BeaconBroadcaster.swift` | The spare device's side: offers the Bluetooth connection, keeps each phone's bedtime hours, and sends a heartbeat every 2 seconds only during them. |
| `Extensions/Monitor` | `DeviceActivityMonitor` that calls `Blocker` at bedtime boundaries. |
| `Extensions/Shield` | The custom "Not in the bedroom" screen. |
| `Extensions/ShieldAction` | The shield's only button, Close. There's no "unlock anyway". |

While apps are blocked, the app's settings are locked too. To change them, leave the room.

## Escape hatch

Like Brick, this isn't airtight on purpose. For a real emergency, go to Settings → Screen Time → Apps with Screen Time Access and turn **Goodnight Phone** off; that removes every block. Opening the app also re-checks the beacon, so a missed "left the room" event fixes itself.

## Adding your partner's phone

Plug their iPhone into the Mac once so Xcode registers it with your team, then press ⌘R with their phone selected. Both phones watch the same beacon, and each person picks their own apps and hours on their own phone.

## No beacon yet?

A spare iPad or iPhone can be the beacon (the app calls this a **bedroom hub**; an ESP32 board flashed with [`hardware/esp32-hub.yaml`](hardware/esp32-hub.yaml) works the same way and needs no screen left on). This works like Brick Night: your phone stays connected to the spare device and decides by signal strength, so you choose where the bedroom ends instead of tuning transmit power.

1. Install Goodnight Phone on the spare device the same way (plug it in, pick it as the run destination, ⌘R). It doesn't need the setup checklist.
2. On the spare device, open **No beacon yet? → Broadcast as bedroom beacon**, turn it on and allow Bluetooth. Leave Goodnight Phone open (any screen), plugged in, by the bed. iOS only keeps this running while the app is on screen, so the display stays on.
3. On your iPhone, tap **Add beacon…** (or **Change beacon…**), then **Use a bedroom hub**, then **Save**, and allow Bluetooth.
4. Once it says **Connected**, stand in the bedroom doorway (not next to the spare device) and tap **Set** on **Bedroom boundary** (or **Set boundary here** under Bedroom beacon). It measures for about five seconds. Nothing is blocked until this is set.

Anywhere the signal is stronger than the boundary counts as the bedroom; weaker counts as outside. During bedtime hours, walking in registers within about 10 seconds and leaving within about 30, with the app open or closed; leaving is slower so a weak moment by the bed doesn't lift the block. Like the other settings, the boundary is locked while apps are blocked, so to move it inward, do it outside bedtime hours.

For battery use, see [Battery](#battery).

**Limits:** whenever your phone can't hear the spare device (out of range, its Goodnight Phone closed or locked, or Bluetooth off on either one), you count as outside. Like the escape hatch below, that isn't airtight. Force-quitting Goodnight Phone on your phone stops detection, and blocking, until you open it again: an "in the bedroom" that hasn't been confirmed in the last minute is ignored, so you're never blocked somewhere else on stale information.

## Troubleshooting

- **Signing error about Family Controls or App Groups.** Select each target, open **Signing & Capabilities**, and make sure your team is selected. Xcode registers the capabilities automatically. If one shows an error, click "Try Again".
- **Shield never appears.** All three extensions need the Family Controls capability, and `project.yml` already sets it. Check that Screen Time access shows as allowed in the app.
- **"Couldn't schedule bedtime hours" in Activity.** Screen Time access was revoked. Allow it again from the setup checklist.
- **Walking in doesn't block anything, but the app shows "In the bedroom" once opened.** Background delivery isn't working. With a real beacon, check that Location is set to Always with Precise on, and that Background App Refresh is on for Goodnight Phone. With a spare iPad or iPhone, check that Bluetooth is allowed for Goodnight Phone on both devices, that Goodnight Phone is open on the spare device, and that you didn't force-quit Goodnight Phone on your phone.
- **With a spare device, blocking switches on and off near the bed.** The boundary was probably set too close to the spare device. Leave the room until it says Outside, then set it again standing in the doorway.
- **Only your own phones.** Development builds are fine for that. Shipping through TestFlight or the App Store requires Apple to approve the Family Controls (Distribution) entitlement separately.

Re-run `./setup.sh` after editing `project.yml`. The `.xcodeproj` is generated, so don't edit it by hand.
