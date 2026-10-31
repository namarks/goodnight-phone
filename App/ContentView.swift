import Combine
import FamilyControls
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var location = LocationPermission()
    @StateObject private var signal = BeaconSignal()
    @ObservedObject private var broadcaster = BeaconBroadcaster.shared
    @ObservedObject private var hub = HubMonitor.shared
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
                hub.setForeground(true)
                broadcaster.restore()
                await model.refreshEverything()
            }
            .onChange(of: model.beacon) { _, beacon in signal.watch(beacon) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    signal.stop()
                    hub.setForeground(false)
                    broadcaster.suspend()
                }
                guard phase == .active else { return }
                location.refresh()
                signal.watch(model.beacon)
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
                button: "Allow"
            ) { Task { await model.requestScreenTime() } }

            if !usesStandIn {
                SetupRow(
                    title: "Location: Always + Precise",
                    detail: location.label,
                    done: location.isReady,
                    button: location.status == .notDetermined ? "Allow" : "Fix"
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
            Text("Setup")
        } footer: {
            Text(usesStandIn
                 ? "Your phone stays connected to the spare device. During bedtime hours it checks the signal every 2 seconds, even when Goodnight Phone is closed. Nothing is blocked until the boundary is set."
                 : "“Always” location lets iOS wake Goodnight Phone when you walk into the bedroom, even when the app is closed. Beacon detection needs Precise Location.")
        }
    }

    private var appsSection: some View {
        Section {
            if model.selection.isEmptySelection {
                Text("No apps selected").foregroundStyle(.secondary)
            }
            ForEach(Array(model.selection.applicationTokens), id: \.self) { token in
                Label(token)
            }
            ForEach(Array(model.selection.categoryTokens), id: \.self) { token in
                Label(token)
            }
            ForEach(Array(model.selection.webDomainTokens), id: \.self) { token in
                Label(token)
            }
            Button("Choose apps…") { openPicker() }
                .disabled(!model.screenTimeApproved || model.isLocked)
        } header: {
            Text("Blocked in the bedroom")
        } footer: {
            appsFooter
        }
    }

    private var tryItSection: some View {
        Section {
            Button("Block these apps for 2 minutes") { model.startTestBlock() }
                .disabled(model.isBlocking)
        } header: {
            Text("Try it now")
        } footer: {
            if let end = model.testEndsAt {
                Text("Test running. Open a blocked app to see the screen. Everything unlocks at \(end.formatted(date: .omitted, time: .shortened)).")
            } else {
                Text("See what blocking looks like without a beacon. Like the real thing, it can't be cancelled early.")
            }
        }
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
            Text("When")
        } footer: {
            Text(model.schedule.limitToHours
                 ? "Tap a day to take that night off. A night runs from its start into the next morning, so Friday is Friday evening to Saturday morning. Blocking starts at bedtime even if you're already in bed."
                 : "Apps are blocked any time you're in the bedroom.")
        }
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
                } else {
                    LabeledContent("Signal") {
                        HStack(spacing: 6) {
                            Text(signal.label)
                            Image(systemName: "cellularbars", variableValue: signal.strength)
                        }
                    }
                    if let pairing = model.blueCharm {
                        BlueCharmRange(pairing: pairing)
                    }
                }
            }
            Button(model.beacon == nil ? "Add beacon…" : "Change beacon…") { editingBeacon = true }
                .disabled(model.isLocked)
        } header: {
            Text("Bedroom beacon")
        } footer: {
            Text(usesStandIn
                 ? "Stronger than the boundary counts as in the bedroom. Set it standing in the bedroom doorway, not next to the spare device; anywhere weaker, like the kitchen, counts as outside. During bedtime hours, walking in registers within about 10 seconds and leaving within about 15, even with the app closed, so a weak moment by the bed doesn't lift the block."
                 : model.blueCharm != nil
                 ? "Signal is live while the app is open. Blocking follows Status, and iOS takes about 30 seconds to register that you've left. If it still says “In the bedroom” after you step out of the room, tap Shorter; if it says “Outside” by the bed, tap Longer."
                 : "Signal is live while the app is open. Blocking follows Status, and iOS takes about 30 seconds to register that you've left. If it still says “In the bedroom” after you step out of the room, turn the beacon's transmit power down.")
        }
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
    }

    private var standInSection: some View {
        Section {
            NavigationLink { StandInBeaconView() } label: {
                LabeledContent("Broadcast as bedroom beacon", value: broadcaster.label)
            }
        } header: {
            // Once this phone has a beacon, "No beacon yet?" reads as if setup isn't finished.
            Text(model.beacon == nil ? "No beacon yet?" : "Spare iPad or iPhone")
        } footer: {
            Text(model.beacon == nil
                 ? "Turn this on in Goodnight Phone on a spare iPad or iPhone to stand in for the beacon while you test."
                 : "Only for a spare device that stays by the bed as the bedroom hub. Your bedroom beacon is set up above.")
        }
    }

    private var activitySection: some View {
        Section("Activity") {
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
        }
    }

    private var aboutSection: some View {
        Section {
            Link("Privacy policy", destination: AppLinks.privacyPolicy)
        } header: {
            Text("About")
        } footer: {
            Text("Everything Goodnight Phone stores stays on this iPhone. In an emergency, turn Goodnight Phone off in Settings → Screen Time → Apps with Screen Time Access to lift every block.")
        }
    }

    @ViewBuilder private var appsFooter: some View {
        if model.isLocked {
            Text("Locked while you're in the bedroom. Leave the room to make changes.")
        } else if model.selection.exceedsShieldLimit {
            Text("iOS blocks at most 50 apps (and 50 sites) at once. Pick whole categories to cover more.")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Helpers

    private func openPicker() {
        pickerSelection = model.selection
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
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, 4)
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .animation(.easeInOut, value: isBlocking)
    }

    private var icon: String {
        if isBlocking { return "moon.zzz.fill" }
        if !setupDone { return "wrench.and.screwdriver.fill" }
        if inRoom { return "bed.double.fill" }
        return "sun.max.fill"
    }

    private var title: String {
        if isBlocking { return "Apps blocked" }
        if !setupDone { return "Finish setup" }
        if inRoom { return "In the bedroom" }
        return "Not in the bedroom"
    }

    private var subtitle: String {
        if isBlocking, let testEndsAt {
            return "Test block. They unlock at \(testEndsAt.formatted(date: .omitted, time: .shortened))."
        }
        if isBlocking { return "They unlock when you leave the room." }
        if !setupDone { return "A few permissions and a beacon, then it runs on its own." }
        if anyTime { return "Apps block whenever you walk in." }
        guard let tonight else {
            return inRoom ? "Tonight's a night off, so nothing's blocked." : "Tonight's a night off, so nothing will block."
        }
        if inRoom { return "Outside bedtime hours (\(tonight)), so nothing's blocked." }
        return "Apps block when you walk in, \(tonight)."
    }

    private var colors: [Color] {
        if isBlocking { return [Color(red: 0.13, green: 0.12, blue: 0.36), Color(red: 0.03, green: 0.04, blue: 0.14)] }
        if !setupDone { return [Color(white: 0.35), Color(white: 0.22)] }
        if inRoom { return [Color(red: 0.33, green: 0.27, blue: 0.62), Color(red: 0.16, green: 0.14, blue: 0.38)] }
        return [Color(red: 0.16, green: 0.52, blue: 0.78), Color(red: 0.10, green: 0.30, blue: 0.55)]
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
    @State private var uuid: String
    @State private var major: String
    @State private var minor: String
    @ObservedObject private var blueCharm = BlueCharm.shared
    private let hadBeacon: Bool
    private let onSave: (BeaconConfig?) -> Void
    private let onSetUpBlueCharm: (BlueCharmPairing) -> Void

    init(
        current: BeaconConfig?,
        onSave: @escaping (BeaconConfig?) -> Void,
        onSetUpBlueCharm: @escaping (BlueCharmPairing) -> Void
    ) {
        _uuid = State(initialValue: current?.uuid ?? "")
        _major = State(initialValue: current?.major.map(String.init) ?? "")
        _minor = State(initialValue: current?.minor.map(String.init) ?? "")
        hadBeacon = current != nil
        self.onSave = onSave
        self.onSetUpBlueCharm = onSetUpBlueCharm
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
        return config.isValid ? config : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        Task {
                            guard let pairing = await blueCharm.setUp() else { return }
                            onSetUpBlueCharm(pairing)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Text("Set up Blue Charm beacon")
                            Spacer()
                            if blueCharm.isBusy { ProgressView() }
                        }
                    }
                    .disabled(blueCharm.isBusy)
                } header: {
                    Text("Blue Charm beacon")
                } footer: {
                    switch blueCharm.phase {
                    case .searching: Text("Looking for it…")
                    case .connecting: Text("Connecting…")
                    case .writing: Text("Setting it up…")
                    case .failed(let message): Text(message).foregroundStyle(.red)
                    case .idle: Text("Plug it into a USB charger by the bed, hold your iPhone next to it, and tap Set up. Goodnight Phone gives it an ID of its own and a bedroom-sized range.")
                    }
                }

                Section {
                    TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $uuid, axis: .vertical)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Other beacons")
                } footer: {
                    Text("Type the beacon's UUID. It's on the box or in the beacon's setup app.")
                }

                Section {
                    Link(destination: AppLinks.recommendedBeacon) {
                        Label("Get the recommended beacon (about $19)", systemImage: "cart")
                    }
                    Button("Use a bedroom hub") {
                        uuid = BeaconConfig.standIn.uuid
                        major = ""
                        minor = ""
                    }
                } header: {
                    Text("No beacon yet?")
                } footer: {
                    Text("The Blue Charm BC-U1 plugs into any USB charger, so there's no battery to run out, and Goodnight Phone sets it up for you.\n\nOr use a bedroom hub: a spare iPad or iPhone running Goodnight Phone (open it there and turn on Broadcast as bedroom beacon), or a hub board. Your phone stays connected to it, and you set where the bedroom ends by standing in the doorway.")
                }

                Section {
                    TextField("Major", text: $major).keyboardType(.numberPad)
                    TextField("Minor", text: $minor).keyboardType(.numberPad)
                } header: {
                    Text("Optional")
                } footer: {
                    Text("Only needed if other beacons nearby share the same UUID. Minor needs a major.")
                }

                if hadBeacon {
                    Section {
                        Button("Remove beacon", role: .destructive) {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Bedroom beacon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft == nil)
                }
            }
        }
    }
}

// MARK: - Blue Charm range

/// Shorter / Longer for a Blue Charm the app set up: steps its transmit power over Bluetooth.
/// Locked while blocking like every other setting, so it can't shrink the bedroom to escape.
private struct BlueCharmRange: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var blueCharm = BlueCharm.shared
    let pairing: BlueCharmPairing

    private var steps: [Int] { BlueCharm.powerSteps }
    private var index: Int { steps.firstIndex(of: pairing.txPower) ?? steps.firstIndex(of: BlueCharm.startingPower)! }

    var body: some View {
        LabeledContent("Range") {
            if blueCharm.isBusy {
                ProgressView()
            } else {
                Text("\(index + 1) of \(steps.count)")
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
        .disabled(model.isLocked || blueCharm.isBusy)
        if case .failed(let message) = blueCharm.phase {
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private func step(_ delta: Int) {
        let power = steps[index + delta]
        Task {
            if let updated = await blueCharm.setPower(power, for: pairing) {
                model.saveBlueCharm(updated)
            }
        }
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
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(Circle().fill(isOn ? Color.accentColor : Color(.tertiarySystemFill)))
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
        }
        .navigationTitle("Hours by night")
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
            if case .hours = night {
                Section {
                    DatePicker("Starts", selection: timeBinding(start: true), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: timeBinding(start: false), displayedComponents: .hourAndMinute)
                }
            }
        }
        .navigationTitle(dayName)
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
                Text("Leave Goodnight Phone open with the device plugged in by the bed. iOS only keeps this running while the app is on screen, so the display stays on while this is on. On your iPhone, open the bedroom beacon settings, tap Use a bedroom hub, then set the bedroom boundary.")
            }
        }
        .navigationTitle("Stand-in beacon")
        .navigationBarTitleDisplayMode(.inline)
    }
}
