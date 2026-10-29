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
                        hours: model.schedule.summary
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if broadcaster.isOn { broadcastingSection }
                if !setupDone { setupSection }
                appsSection
                hoursSection
                beaconSection
                standInSection
                activitySection
            }
            .navigationTitle("Lights Out")
            .familyActivityPicker(isPresented: $showingPicker, selection: $pickerSelection)
            .onChange(of: showingPicker) { _, isShowing in
                if !isShowing { model.saveSelection(pickerSelection) }
            }
            .sheet(isPresented: $editingBeacon) {
                BeaconEditor(current: model.beacon) { model.saveBeacon($0) }
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
                detail: model.screenTimeApproved ? "Allowed" : "Lets Lights Out block apps",
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
                 ? "Your phone stays connected to the spare device and checks the signal every second, even when Lights Out is closed. Nothing is blocked until the boundary is set."
                 : "“Always” location lets iOS wake Lights Out when you walk into the bedroom, even when the app is closed. Beacon detection needs Precise Location.")
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

    private var hoursSection: some View {
        Section {
            Toggle("Only during bedtime hours", isOn: scheduleBinding(\.limitToHours))
            if model.schedule.limitToHours {
                DatePicker("Starts", selection: timeBinding(\.startMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: timeBinding(\.endMinutes), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("When")
        } footer: {
            Text(model.schedule.limitToHours
                 ? "Blocking starts at bedtime even if you're already in bed, and lifts in the morning."
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
                }
            }
            Button(model.beacon == nil ? "Add beacon…" : "Change beacon…") { editingBeacon = true }
                .disabled(model.isLocked)
        } header: {
            Text("Bedroom beacon")
        } footer: {
            Text(usesStandIn
                 ? "Stronger than the boundary counts as in the bedroom. Set it standing in the bedroom doorway, not next to the spare device; anywhere weaker, like the kitchen, counts as outside. During bedtime hours, walking in registers within about 10 seconds and leaving within about 30, even with the app closed, so a weak moment by the bed doesn't lift the block."
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
            Text("This device is standing in for the bedroom beacon. Keep Lights Out open, plugged in, by the bed.")
        }
    }

    private var standInSection: some View {
        Section {
            NavigationLink { StandInBeaconView() } label: {
                LabeledContent("Broadcast as bedroom beacon", value: broadcaster.label)
            }
        } header: {
            Text("No beacon yet?")
        } footer: {
            Text("Turn this on in Lights Out on a spare iPad or iPhone to stand in for the beacon while you test.")
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
    let hours: String

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
        if !setupDone { return "wrench.and.screwdriver.fill" }
        if isBlocking { return "moon.zzz.fill" }
        if inRoom { return "bed.double.fill" }
        return "sun.max.fill"
    }

    private var title: String {
        if !setupDone { return "Finish setup" }
        if isBlocking { return "Apps blocked" }
        if inRoom { return "In the bedroom" }
        return "Not in the bedroom"
    }

    private var subtitle: String {
        if !setupDone { return "A few permissions and a beacon, then it runs on its own." }
        if isBlocking { return "They unlock when you leave the room." }
        if inRoom { return "Outside bedtime hours (\(hours)), so nothing's blocked." }
        return hours == "Any time"
            ? "Apps block whenever you walk in."
            : "Apps block when you walk in, \(hours)."
    }

    private var colors: [Color] {
        if !setupDone { return [Color(white: 0.35), Color(white: 0.22)] }
        if isBlocking { return [Color(red: 0.13, green: 0.12, blue: 0.36), Color(red: 0.03, green: 0.04, blue: 0.14)] }
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
    private let hadBeacon: Bool
    private let onSave: (BeaconConfig?) -> Void

    init(current: BeaconConfig?, onSave: @escaping (BeaconConfig?) -> Void) {
        _uuid = State(initialValue: current?.uuid ?? "")
        _major = State(initialValue: current?.major.map(String.init) ?? "")
        _minor = State(initialValue: current?.minor.map(String.init) ?? "")
        hadBeacon = current != nil
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
        return config.isValid ? config : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $uuid, axis: .vertical)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Beacon UUID")
                } footer: {
                    Text("It's on the box or in the beacon's setup app.")
                }

                Section {
                    Button("Use a spare iPad or iPhone") {
                        uuid = BeaconConfig.standIn.uuid
                        major = ""
                        minor = ""
                    }
                } header: {
                    Text("No beacon yet?")
                } footer: {
                    Text("Your phone connects to a spare iPad or iPhone running Lights Out, and you set where the bedroom ends by signal strength. On the spare device, open Lights Out and turn on Broadcast as bedroom beacon.")
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
                Text("Leave Lights Out open with the device plugged in by the bed. iOS only keeps this running while the app is on screen, so the display stays on while this is on. On your iPhone, open the bedroom beacon settings, tap Use a spare iPad or iPhone, then set the bedroom boundary.")
            }
        }
        .navigationTitle("Stand-in beacon")
        .navigationBarTitleDisplayMode(.inline)
    }
}
