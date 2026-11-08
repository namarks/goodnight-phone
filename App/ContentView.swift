import Combine
import FamilyControls
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var location = LocationPermission()
    @StateObject private var signal = BeaconSignal()
    @ObservedObject private var broadcaster = BeaconBroadcaster.shared
    @ObservedObject private var hub = HubMonitor.shared
    @ObservedObject private var blueCharm = BlueCharm.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingPicker = false
    @State private var pickerSelection = FamilyActivitySelection()
    @State private var editingBeacon = false

    /// Keeps the status card current if bedtime starts while the app is open.
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// The spare-device stand-in is watched over Bluetooth, so it needs a boundary instead of location.
    private var usesStandIn: Bool { model.beacon?.isStandIn == true }

    private var setupDone: Bool {
        guard model.screenTimeApproved, !model.selection.isEmptySelection, model.beacon != nil else { return false }
        return usesStandIn ? hub.boundary != nil && hub.link != .notAllowed : location.isReady
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StatusCard(
                        setupDone: setupDone,
                        isBlocking: model.isBlocking,
                        inRoom: model.inRoom,
                        anyTime: !model.schedule.limitToHours,
                        tonight: model.schedule.currentNight(),
                        testEndsAt: model.testEndsAt
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if broadcaster.isOn { broadcastingSection }
                if !setupDone { setupSection }
                appsSection
                if model.screenTimeApproved && !model.selection.isEmptySelection { tryItSection }
                hoursSection
                beaconSection
                standInSection
                activitySection
                aboutSection
            }
            .navigationTitle("Goodnight Phone")
            .brandForm()
            .readableWidth()
            .familyActivityPicker(isPresented: $showingPicker, selection: $pickerSelection)
            .onChange(of: showingPicker) { _, isShowing in
                if !isShowing { model.saveSelection(pickerSelection) }
            }
            .sheet(isPresented: $editingBeacon) {
                BeaconEditor(
                    current: model.beacon,
                    onSave: { model.saveBeacon($0) },
                    onSetUpBlueCharm: { model.saveBlueCharm($0) }
                )
            }
            .task {
                signal.watch(model.beacon)
                blueCharm.watchSignal(of: model.blueCharm)
                hub.setForeground(true)
                broadcaster.restore()
                await model.refreshEverything()
            }
            .onChange(of: model.beacon) { _, beacon in signal.watch(beacon) }
            .onChange(of: model.blueCharm?.peripheralID) { _, _ in
                if scenePhase != .background { blueCharm.watchSignal(of: model.blueCharm) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    signal.stop()
                    blueCharm.watchSignal(of: nil)
                    hub.setForeground(false)
                    broadcaster.suspend()
                }
                guard phase == .active else { return }
                location.refresh()
                signal.watch(model.beacon)
                blueCharm.watchSignal(of: model.blueCharm)
                hub.setForeground(true)
                broadcaster.resume()
                Task { await model.refreshEverything() }
            }
            .onReceive(ticker) { _ in model.reload() }
        }
    }

    // MARK: - Sections

    private var setupSection: some View {
        Section {
            SetupRow(
                title: "Screen Time access",
                detail: model.screenTimeApproved ? "Allowed" : "Lets Goodnight Phone block apps",
                done: model.screenTimeApproved,
                button: "Continue"
            ) { Task { await model.requestScreenTime() } }

            if !usesStandIn {
                SetupRow(
                    title: "Location: Always + Precise",
                    detail: location.label,
                    done: location.isReady,
                    button: location.status == .notDetermined ? "Continue" : "Fix"
                ) { location.request() }
            }

            SetupRow(
                title: "Apps to block",
                detail: model.selection.summary,
                done: !model.selection.isEmptySelection,
                button: "Choose",
                enabled: model.screenTimeApproved
            ) { openPicker() }

            SetupRow(
                title: "Bedroom beacon",
                detail: model.beacon?.displayName ?? "Not set",
                done: model.beacon != nil,
                button: "Add"
            ) { editingBeacon = true }

            if usesStandIn {
                SetupRow(
                    title: "Bedroom boundary",
                    detail: hub.isListening
                        ? (hub.isCalibrating ? "Measuring…" : "Stand at the bedroom door, then tap Set")
                        : hub.linkLabel,
                    done: hub.boundary != nil,
                    button: "Set",
                    enabled: hub.isListening && !hub.isCalibrating
                ) { hub.calibrate() }
            }
        } header: {
            BrandHeader("Setup")
        } footer: {
            Text(usesStandIn
                 ? "Your phone stays connected to the spare device. During bedtime hours it checks the signal every 2 seconds, even when Goodnight Phone is closed. Nothing is blocked until the boundary is set."
                 : "“Always” location lets iOS wake Goodnight Phone when you walk into the bedroom, even when the app is closed. Beacon detection needs Precise Location.")
        }
        .brandRow()
    }

    private var appsSection: some View {
        Section {
            if model.selection.isEmptySelection {
                Text("No apps selected").foregroundStyle(.secondary)
            }
            let selection = model.selection
            if selection.categoryTokens.isEmpty {
                ForEach(Array(selection.applicationTokens), id: \.self) { Label($0) }
                ForEach(Array(selection.webDomainTokens), id: \.self) { Label($0) }
            } else {
                // A ticked category also adds each of its apps and sites by name (so iOS can't
                // skip one), and the picker doesn't say which were picked one by one. So list
                // the categories and give one total that includes them.
                ForEach(Array(selection.categoryTokens), id: \.self) { Label($0) }
                Text(selection.coverage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Choose apps…") { openPicker() }
                .disabled(!model.screenTimeApproved || model.isLocked)
        } header: {
            BrandHeader("The goodnight list")
        } footer: {
            appsFooter
        }
        .brandRow()
    }

    private var tryItSection: some View {
        Section {
            if model.testEndsAt != nil {
                Button("Stop test", role: .destructive) { model.stopTestBlock() }
            } else {
                Button("Block these apps for 2 minutes") { model.startTestBlock() }
                    .disabled(model.isBlocking)
            }
        } header: {
            BrandHeader("Try it now")
        } footer: {
            if let end = model.testEndsAt {
                Text("Test running. Open a blocked app to see the screen. It ends at \(end.formatted(date: .omitted, time: .shortened)), or tap Stop test.")
            } else {
                Text("See what blocking looks like without a beacon. You can stop the test early; that never lifts a real bedtime block.")
            }
        }
        .brandRow()
    }

    private var hoursSection: some View {
        Section {
            Toggle("Only during bedtime hours", isOn: scheduleBinding(\.limitToHours))
            if model.schedule.limitToHours {
                NightToggles()
                DatePicker("Starts", selection: timeBinding(\.startMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: timeBinding(\.endMinutes), displayedComponents: .hourAndMinute)
                NavigationLink { NightsView() } label: {
                    LabeledContent("Hours by night", value: model.schedule.nightsSummary)
                }
            }
        } header: {
            BrandHeader("When")
        } footer: {
            Text(model.schedule.limitToHours
                 ? "Tap a day to take that night off. A night runs from its start into the next morning, so Friday is Friday evening to Saturday morning. Blocking starts at bedtime even if you're already in bed."
                 : "Apps are blocked any time you're in the bedroom.")
        }
        .brandRow()
        .disabled(model.isLocked)
    }

    private var beaconSection: some View {
        Section {
            if let beacon = model.beacon {
                LabeledContent("Beacon", value: beacon.displayName)
                LabeledContent("Status", value: model.inRoom ? "In the bedroom" : "Outside")
                if beacon.isStandIn {
                    LabeledContent("Connection", value: hub.linkLabel)
                    LabeledContent("Signal") {
                        HStack(spacing: 6) {
                            Text(hub.rssi.map { "\($0) dBm" } ?? "—")
                            Image(systemName: "cellularbars", variableValue: hub.strength)
                        }
                    }
                    LabeledContent("Boundary", value: hub.boundary.map { "\($0) dBm" } ?? "Not set")
                    Button(hub.isCalibrating ? "Measuring…" : "Set boundary here") { hub.calibrate() }
                        .disabled(model.isLocked || !hub.isListening || hub.isCalibrating)
                } else if let pairing = model.blueCharm {
                    // A Blue Charm's signal comes straight from its Bluetooth advertising.
                    LabeledContent("Signal") {
                        HStack(spacing: 6) {
                            Text(blueCharm.signalRSSI.map { "\($0) dBm" } ?? "Not detected")
                            Image(systemName: "cellularbars", variableValue: BeaconSignal.strength(rssi: blueCharm.signalRSSI))
                        }
                    }
                    BlueCharmRange(pairing: pairing)
                } else {
                    LabeledContent("Signal") {
                        HStack(spacing: 6) {
                            Text(signal.label)
                            Image(systemName: "cellularbars", variableValue: signal.strength)
                        }
                    }
                }
            }
            Button(model.beacon == nil ? "Add beacon…" : "Change beacon…") { editingBeacon = true }
                .disabled(model.isLocked)
            // Read-only, so it stays open while apps are blocked.
            NavigationLink { BeaconPlacementGuide() } label: {
                Label("Where to put the beacon", systemImage: "lightbulb")
            }
        } header: {
            BrandHeader("Bedroom beacon")
        } footer: {
            Text(usesStandIn
                 ? "Stronger than the boundary counts as in the bedroom. Set it standing in the bedroom doorway, not next to the spare device; anywhere weaker, like the kitchen, counts as outside. During bedtime hours, walking in registers within about 10 seconds and leaving within about 15, even with the app closed, so a weak moment by the bed doesn't lift the block."
                 : model.blueCharm != nil
                 ? "Signal is live while the app is open. Blocking follows Status, and iOS takes about 30 seconds to register that you've left. If it still says “In the bedroom” after you step out of the room, tap Shorter; if it says “Outside” by the bed, tap Longer. For 15 minutes after setup these work even while apps are blocked."
                 : "Signal is live while the app is open. Blocking follows Status, and iOS takes about 30 seconds to register that you've left. If it still says “In the bedroom” after you step out of the room, turn the beacon's transmit power down.")
        }
        .brandRow()
    }

    /// Shown at the top while this device is the stand-in beacon. Kept separate from
    /// standInSection so the NavigationLink never moves (moving it would pop its screen).
    private var broadcastingSection: some View {
        Section {
            LabeledContent {
                Text(broadcaster.label)
            } label: {
                Label("Stand-in beacon", systemImage: "dot.radiowaves.left.and.right")
            }
        } footer: {
            Text("This device is standing in for the bedroom beacon. Keep Goodnight Phone open, plugged in, by the bed.")
        }
        .brandRow()
    }

    private var standInSection: some View {
        Section {
            NavigationLink { StandInBeaconView() } label: {
                LabeledContent("Broadcast as bedroom beacon", value: broadcaster.label)
            }
        } header: {
            // Once this phone has a beacon, "No beacon yet?" reads as if setup isn't finished.
            BrandHeader(model.beacon == nil ? "No beacon yet?" : "Spare iPad or iPhone")
        } footer: {
            Text(model.beacon == nil
                 ? "Turn this on in Goodnight Phone on a spare iPad or iPhone to stand in for the beacon while you test."
                 : "Only for a spare device that stays by the bed as the bedroom hub. Your bedroom beacon is set up above.")
        }
        .brandRow()
    }

    private var activitySection: some View {
        Section {
            if model.log.isEmpty {
                Text("Nothing yet").foregroundStyle(.secondary)
            }
            ForEach(model.log.prefix(25)) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.message)
                    Text(entry.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            BrandHeader("Activity")
        }
        .brandRow()
    }

    private var aboutSection: some View {
        Section {
            Link("Privacy policy", destination: AppLinks.privacyPolicy)
        } header: {
            BrandHeader("About")
        } footer: {
            Text("Everything Goodnight Phone stores stays on this iPhone. In an emergency, turn Goodnight Phone off in Settings → Screen Time → Apps with Screen Time Access to lift every block.")
        }
        .brandRow()
    }

    @ViewBuilder private var appsFooter: some View {
        if model.isLocked {
            Text("Locked while you're in the bedroom. Leave the room to make changes.")
        } else if model.selection.exceedsShieldLimit {
            Text("That's more apps or sites than Goodnight Phone can block (\(Blocker.tokensPerStore * Blocker.maxStores) each). Pick whole categories to cover more.")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Helpers

    private func openPicker() {
        // includeEntireCategory: ticking a category also adds each of its apps by name.
        // iOS's category block skipped Instagram on a real phone while blocking it by name
        // worked, so Blocker shields both (split across stores past 50 apps).
        if model.selection.includeEntireCategory {
            pickerSelection = model.selection
        } else {
            var selection = FamilyActivitySelection(includeEntireCategory: true)
            selection.applicationTokens = model.selection.applicationTokens
            selection.categoryTokens = model.selection.categoryTokens
            selection.webDomainTokens = model.selection.webDomainTokens
            pickerSelection = selection
        }
        showingPicker = true
    }

    private func scheduleBinding(_ keyPath: WritableKeyPath<BedtimeSchedule, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.schedule[keyPath: keyPath] },
            set: { newValue in
                var schedule = model.schedule
                schedule[keyPath: keyPath] = newValue
                model.saveSchedule(schedule)
            }
        )
    }

    private func timeBinding(_ keyPath: WritableKeyPath<BedtimeSchedule, Int>) -> Binding<Date> {
        Binding(
            get: { BedtimeSchedule.date(fromMinutes: model.schedule[keyPath: keyPath]) },
            set: { newValue in
                var schedule = model.schedule
                schedule[keyPath: keyPath] = BedtimeSchedule.minutes(from: newValue)
                model.saveSchedule(schedule)
            }
        )
    }
}

// MARK: - Status card

private struct StatusCard: View {
    let setupDone: Bool
    let isBlocking: Bool
    let inRoom: Bool
    let anyTime: Bool
    /// Tonight's hours (or last night's, until they end); nil on a night off.
    let tonight: String?
    let testEndsAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .padding(.bottom, 4)
            Text(title)
                .font(Brand.heading(28))
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .opacity(0.9)
        }
        .foregroundStyle(textColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Brand.fixedInk, lineWidth: 2.5))
        // A solid offset shadow, like ink on a printed page.
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Brand.fixedInk)
                .offset(x: 4, y: 4)
        )
        .padding(.trailing, 4)
        .padding(.bottom, 4)
        .animation(.easeInOut, value: isBlocking)
    }

    private var icon: String {
        if isBlocking { return "moon.zzz.fill" }
        if !setupDone { return "wrench.and.screwdriver.fill" }
        if inRoom { return "bed.double.fill" }
        return "sun.max.fill"
    }

    private var title: String {
        if isBlocking { return "Apps asleep" }
        if !setupDone { return "Finish setup" }
        if inRoom { return "In the bedroom" }
        return "Not in the bedroom"
    }

    private var subtitle: String {
        if isBlocking, let testEndsAt {
            return "Test block. They wake up at \(testEndsAt.formatted(date: .omitted, time: .shortened))."
        }
        if isBlocking { return "They wake up when you leave the room." }
        if !setupDone { return "A few permissions and a beacon, then it runs on its own." }
        if anyTime { return "Apps block whenever you walk in." }
        guard let tonight else {
            return inRoom ? "Tonight's a night off, so nothing's blocked." : "Tonight's a night off, so nothing will block."
        }
        if inRoom { return "Outside bedtime hours (\(tonight)), so nothing's blocked." }
        return "Apps block when you walk in, \(tonight)."
    }

    /// Night window when apps are asleep, nursery green in the bedroom, moon yellow outside it.
    private var fill: Color {
        if isBlocking { return Brand.night }
        if !setupDone { return Brand.cream }
        if inRoom { return Color(red: 0x2F / 255, green: 0x6B / 255, blue: 0x45 / 255) }
        return Color(red: 0xF2 / 255, green: 0xC8 / 255, blue: 0x49 / 255)
    }

    private var textColor: Color {
        isBlocking || (setupDone && inRoom) ? Brand.cream : Brand.fixedInk
    }

    private var iconColor: Color {
        if isBlocking { return Color(red: 0xF2 / 255, green: 0xC8 / 255, blue: 0x49 / 255) }
        if setupDone && !inRoom { return Color(red: 0xC2 / 255, green: 0x3B / 255, blue: 0x2E / 255) }
        return textColor
    }
}

// MARK: - Setup row

private struct SetupRow: View {
    let title: String
    let detail: String
    let done: Bool
    let button: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !done {
                Button(button, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!enabled)
            }
        }
    }
}

// MARK: - Beacon editor

private struct BeaconEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var blueCharm = BlueCharm.shared
    private let current: BeaconConfig?
    @State private var saved: [BeaconConfig]
    private let onSave: (BeaconConfig?) -> Void
    private let onSetUpBlueCharm: (BlueCharmPairing) -> Void

    init(
        current: BeaconConfig?,
        onSave: @escaping (BeaconConfig?) -> Void,
        onSetUpBlueCharm: @escaping (BlueCharmPairing) -> Void
    ) {
        self.current = current
        var saved = Shared.savedBeacons
        if let current, !saved.contains(current) { saved.insert(current, at: 0) }
        _saved = State(initialValue: saved)
        self.onSave = onSave
        self.onSetUpBlueCharm = onSetUpBlueCharm
    }

    private func pick(_ beacon: BeaconConfig?) {
        onSave(beacon)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                if !saved.isEmpty {
                    Section {
                        ForEach(saved, id: \.self) { beacon in
                            Button { pick(beacon) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(beacon.displayName).foregroundStyle(Color.primary)
                                        Text(detail(for: beacon)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if beacon == current {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            // The current beacon stays listed; switch away first to remove it.
                            .deleteDisabled(beacon == current)
                        }
                        .onDelete { offsets in
                            saved.remove(atOffsets: offsets)
                            Shared.savedBeacons = saved
                        }
                    } header: {
                        BrandHeader("Your beacons")
                    } footer: {
                        Text("Tap one to switch to it.")
                    }
                    .brandRow()
                }

                Section {
                    NavigationLink {
                        HubSetupView(isCurrent: current?.isStandIn == true) { pick(BeaconConfig.standIn) }
                    } label: {
                        Label("Use a bedroom hub", systemImage: "dot.radiowaves.left.and.right")
                    }

                    Button {
                        Task {
                            guard let pairing = await blueCharm.setUp() else { return }
                            onSetUpBlueCharm(pairing)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Label("Set up a Blue Charm beacon", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            if blueCharm.isBusy { ProgressView() }
                        }
                    }
                    .disabled(blueCharm.isBusy)

                    NavigationLink {
                        OtherBeaconForm(current: current?.isStandIn == false ? current : nil) { pick($0) }
                    } label: {
                        Label("Another iBeacon", systemImage: "number")
                    }

                    NavigationLink { BeaconPlacementGuide() } label: {
                        Label("Where to put it", systemImage: "lightbulb")
                    }
                } header: {
                    BrandHeader("Add a beacon")
                } footer: {
                    switch blueCharm.phase {
                    case .searching: Text("Looking for the Blue Charm…")
                    case .connecting: Text("Connecting…")
                    case .writing: Text("Setting it up…")
                    case .failed(let message): Text(message).foregroundStyle(.red)
                    case .idle, .holding: Text("Blue Charm: plug it into a USB charger by the bed. For the battery one, twist it open, hold the white button inside for 3 seconds until the light flashes red, and close it. Then hold your iPhone next to it and tap Set up.")
                    }
                }
                .brandRow()

                Section {
                    Link(destination: AppLinks.chooseBeacon) {
                        Label("Choose a beacon", systemImage: "cart")
                    }
                } header: {
                    BrandHeader("No beacon yet?")
                } footer: {
                    Text("The bedroom hub is the most precise: you set exactly where the bedroom ends, and leaving lifts the block within seconds. It's about $15 in parts and needs a one-time install from a computer. No computer? The Blue Charm BC-U1 plugs into any USB charger and Goodnight Phone sets it up for you, but iOS decides when you've left, which can take a minute or more.")
                }
                .brandRow()

                if current != nil {
                    Section {
                        Button("Remove beacon", role: .destructive) { pick(nil) }
                    }
                    .brandRow()
                }
            }
            .navigationTitle("Bedroom beacon")
            .brandForm()
            .readableWidth()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func detail(for beacon: BeaconConfig) -> String {
        if beacon.isStandIn { return "Bedroom hub. Set the door boundary again after switching." }
        if Shared.blueCharm?.uuid == beacon.uuid { return "Set up in Goodnight Phone" }
        return "iBeacon"
    }
}

/// Setting up a bedroom hub: get the parts, install it from a computer, plug it in by the bed.
/// The app never links to a store (the website holds the shopping links), and the install needs
/// Chrome or Edge on a computer, so the app shares that link instead of opening it.
private struct HubSetupView: View {
    let isCurrent: Bool
    let onUse: () -> Void

    var body: some View {
        Form {
            Section {
                Text("A thumbnail-sized Bluetooth board that stays plugged in by your bed. You set exactly where the bedroom ends by standing in the doorway, and walking out lifts the block within seconds. One hub works for up to three phones, each with its own bedtime.")
            }
            .brandRow()

            Section {
                Link(destination: AppLinks.chooseBeacon) {
                    Label("See the parts", systemImage: "cart")
                }
            } header: {
                BrandHeader("1. Get the parts")
            } footer: {
                Text("A Seeed XIAO ESP32-C6 and a small USB-C adapter, about $15 together, plus a USB-C charger or power strip by the bed.")
            }
            .brandRow()

            Section {
                ShareLink(item: AppLinks.hubInstall) {
                    Label("Send the install link to your computer", systemImage: "laptopcomputer")
                }
            } header: {
                BrandHeader("2. Install it from a computer")
            } footer: {
                Text("Open the link in Chrome or Edge on a Mac or PC, plug the board in with a USB-C cable and click Install. It takes about a minute, once. An iPhone or iPad can't do this step.")
            }
            .brandRow()

            Section {
                Button(isCurrent ? "This is your bedroom beacon" : "Use the bedroom hub", action: onUse)
                    .disabled(isCurrent)
            } header: {
                BrandHeader("3. Plug it in by the bed")
            } footer: {
                Text("Put it on the far side of the bed from the door. Then tap the button above, stand in the bedroom doorway and tap Set boundary here. A spare iPad or iPhone running Goodnight Phone with Broadcast as bedroom beacon on works as a hub too.")
            }
            .brandRow()
        }
        .navigationTitle("Bedroom hub")
        .brandForm()
        .readableWidth()
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Typing in any other iBeacon's identity.
private struct OtherBeaconForm: View {
    @State private var uuid: String
    @State private var major: String
    @State private var minor: String
    private let onSave: (BeaconConfig) -> Void

    init(current: BeaconConfig?, onSave: @escaping (BeaconConfig) -> Void) {
        _uuid = State(initialValue: current?.uuid ?? "")
        _major = State(initialValue: current?.major.map(String.init) ?? "")
        _minor = State(initialValue: current?.minor.map(String.init) ?? "")
        self.onSave = onSave
    }

    /// nil when the fields don't make a valid beacon.
    private var draft: BeaconConfig? {
        let majorText = major.trimmingCharacters(in: .whitespaces)
        let minorText = minor.trimmingCharacters(in: .whitespaces)
        let majorValue = UInt16(majorText)
        let minorValue = UInt16(minorText)
        if !majorText.isEmpty, majorValue == nil { return nil }
        if !minorText.isEmpty, minorValue == nil { return nil }
        let config = BeaconConfig(
            uuid: uuid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            major: majorValue,
            minor: minorValue
        )
        return config.isValid && !config.isStandIn ? config : nil
    }

    var body: some View {
        Form {
            Section {
                TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $uuid, axis: .vertical)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } header: {
                BrandHeader("Beacon UUID")
            } footer: {
                Text("It's on the box or in the beacon's setup app.")
            }
            .brandRow()

            Section {
                TextField("Major", text: $major).keyboardType(.numberPad)
                TextField("Minor", text: $minor).keyboardType(.numberPad)
            } header: {
                BrandHeader("Optional")
            } footer: {
                Text("Only needed if other beacons nearby share the same UUID. Minor needs a major.")
            }
            .brandRow()
        }
        .navigationTitle("Another iBeacon")
        .brandForm()
        .readableWidth()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if let draft { onSave(draft) } }
                    .disabled(draft == nil)
            }
        }
    }
}

// MARK: - Blue Charm range

/// Shorter / Longer for a Blue Charm the app set up: steps its transmit power over Bluetooth.
/// Locked while blocking like every other setting, so it can't shrink the bedroom to escape,
/// except during the tuning window right after setup (BlueCharmPairing.tuningWindow).
private struct BlueCharmRange: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var blueCharm = BlueCharm.shared
    let pairing: BlueCharmPairing

    private var steps: [Int] { BlueCharm.powerSteps }
    /// The step last tapped, even before the beacon has it, so each tap shows at once.
    private var power: Int { blueCharm.targetPower ?? pairing.txPower }
    private var index: Int { steps.firstIndex(of: power) ?? steps.firstIndex(of: BlueCharm.startingPower)! }
    /// Busy with something other than a range change (setup), when the buttons wait.
    private var otherJob: Bool { blueCharm.isBusy && blueCharm.targetPower == nil }

    var body: some View {
        LabeledContent("Range") {
            HStack(spacing: 8) {
                if blueCharm.targetPower != nil, blueCharm.phase != .holding {
                    ProgressView()
                }
                Text("\(index + 1) of \(steps.count)")
                    .monospacedDigit()
            }
        }
        HStack {
            Button("Shorter") { step(-1) }
                .disabled(index == 0)
            Spacer()
            Button("Longer") { step(1) }
                .disabled(index == steps.count - 1)
        }
        // Borderless, or a tap anywhere in the row would press both buttons.
        .buttonStyle(.borderless)
        .disabled((model.isLocked && !pairing.inTuningWindow()) || otherJob)
        if case .failed(let message) = blueCharm.phase {
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private func step(_ delta: Int) {
        blueCharm.requestPower(steps[index + delta], for: pairing) { model.saveBlueCharm($0) }
    }
}

// MARK: - Nights

private enum Weekdays {
    /// Calendar weekdays (1 = Sunday), starting on the locale's first day of the week.
    static var inOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}

/// One circle per night, like the Clock app's alarm days: filled = blocking that night.
private struct NightToggles: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack {
            ForEach(Weekdays.inOrder, id: \.self) { weekday in
                let isOn = model.schedule.hours(onWeekday: weekday) != nil
                Button {
                    var schedule = model.schedule
                    // Back on uses the usual hours; a night's own hours are set under Hours by night.
                    schedule.nights[weekday - 1] = isOn ? .off : .usual
                    model.saveSchedule(schedule)
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(isOn ? Brand.cream : Color.primary)
                        .background(Circle().fill(isOn ? Brand.red : Color(.tertiarySystemFill)))
                }
                // Borderless, or a tap anywhere in the row would press every button.
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(Calendar.current.weekdaySymbols[weekday - 1]) night")
                .accessibilityValue(isOn ? "On" : "Off")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NightsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(Weekdays.inOrder, id: \.self) { weekday in
                    NavigationLink { NightEditor(weekday: weekday) } label: {
                        LabeledContent(Calendar.current.weekdaySymbols[weekday - 1], value: hours(weekday))
                    }
                }
            } footer: {
                Text("Give a night its own hours, or take it off. Nights on usual hours follow Starts and Ends.")
            }
            .brandRow()
        }
        .navigationTitle("Hours by night")
        .brandForm()
        .readableWidth()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isLocked)
    }

    private func hours(_ weekday: Int) -> String {
        guard let hours = model.schedule.hours(onWeekday: weekday) else { return "Off" }
        return BedtimeSchedule.summary(start: hours.start, end: hours.end)
    }
}

private struct NightEditor: View {
    @EnvironmentObject private var model: AppModel
    /// Calendar weekday, 1 = Sunday.
    let weekday: Int

    private enum Choice: Hashable { case usual, own, off }

    private var night: BedtimeSchedule.Night { model.schedule.nights[weekday - 1] }
    private var dayName: String { Calendar.current.weekdaySymbols[weekday - 1] }
    private var nextDayName: String { Calendar.current.weekdaySymbols[weekday % 7] }

    var body: some View {
        Form {
            Section {
                Picker("Hours", selection: choiceBinding) {
                    Text("Usual hours").tag(Choice.usual)
                    Text("Different hours").tag(Choice.own)
                    Text("Off").tag(Choice.off)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                switch night {
                case .usual:
                    Text("\(BedtimeSchedule.summary(start: model.schedule.startMinutes, end: model.schedule.endMinutes)), like the other nights on usual hours.")
                case .hours:
                    Text("Only \(dayName) night. The usual hours stay as they are.")
                case .off:
                    Text("Nothing is blocked from \(dayName) evening through \(nextDayName) morning.")
                }
            }
            .brandRow()
            if case .hours = night {
                Section {
                    DatePicker("Starts", selection: timeBinding(start: true), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: timeBinding(start: false), displayedComponents: .hourAndMinute)
                }
                .brandRow()
            }
        }
        .navigationTitle(dayName)
        .brandForm()
        .readableWidth()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isLocked)
    }

    private var choiceBinding: Binding<Choice> {
        Binding(
            get: {
                switch night {
                case .usual: return .usual
                case .hours: return .own
                case .off: return .off
                }
            },
            set: { choice in
                switch choice {
                case .usual: save(.usual)
                case .off: save(.off)
                case .own:
                    if case .hours = night { return }
                    // Start from the usual hours, ready to adjust.
                    save(.hours(start: model.schedule.startMinutes, end: model.schedule.endMinutes))
                }
            }
        )
    }

    private func timeBinding(start: Bool) -> Binding<Date> {
        Binding(
            get: {
                guard case .hours(let s, let e) = night else { return .now }
                return BedtimeSchedule.date(fromMinutes: start ? s : e)
            },
            set: { newValue in
                guard case .hours(let s, let e) = night else { return }
                let minutes = BedtimeSchedule.minutes(from: newValue)
                save(start ? .hours(start: minutes, end: e) : .hours(start: s, end: minutes))
            }
        )
    }

    private func save(_ newValue: BedtimeSchedule.Night) {
        var schedule = model.schedule
        schedule.nights[weekday - 1] = newValue
        model.saveSchedule(schedule)
    }
}

// MARK: - Stand-in beacon

private struct StandInBeaconView: View {
    @ObservedObject private var broadcaster = BeaconBroadcaster.shared

    var body: some View {
        Form {
            Section {
                Toggle("Broadcast as bedroom beacon", isOn: Binding(
                    get: { broadcaster.isOn },
                    set: { broadcaster.setOn($0) }
                ))
                LabeledContent("Status", value: broadcaster.label)
            } footer: {
                Text("Leave Goodnight Phone open with the device plugged in by the bed. iOS only keeps this running while the app is on screen, so the display stays on while this is on. On your iPhone, open the bedroom beacon settings, tap Use a bedroom hub, then Use the bedroom hub, then set the bedroom boundary.")
            }
            .brandRow()
        }
        .navigationTitle("Stand-in beacon")
        .brandForm()
        .readableWidth()
        .navigationBarTitleDisplayMode(.inline)
    }
}
