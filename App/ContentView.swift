import Combine
import FamilyControls
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var location = LocationPermission()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingPicker = false
    @State private var pickerSelection = FamilyActivitySelection()
    @State private var editingBeacon = false

    /// Keeps the status card current if bedtime starts while the app is open.
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var setupDone: Bool {
        model.screenTimeApproved && location.isReady
            && !model.selection.isEmptySelection && model.beacon != nil
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

                if !setupDone { setupSection }
                appsSection
                hoursSection
                beaconSection
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
            .task { await model.refreshEverything() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                location.refresh()
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

            SetupRow(
                title: "Location: Always + Precise",
                detail: location.label,
                done: location.isReady,
                button: location.status == .notDetermined ? "Allow" : "Fix"
            ) { location.request() }

            SetupRow(
                title: "Apps to block",
                detail: model.selection.summary,
                done: !model.selection.isEmptySelection,
                button: "Choose",
                enabled: model.screenTimeApproved
            ) { openPicker() }

            SetupRow(
                title: "Bedroom beacon",
                detail: model.beacon?.shortDescription ?? "Not set",
                done: model.beacon != nil,
                button: "Add"
            ) { editingBeacon = true }
        } header: {
            Text("Setup")
        } footer: {
            Text("“Always” location lets iOS wake Lights Out when you walk into the bedroom, even when the app is closed. Beacon detection needs Precise Location.")
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
                LabeledContent("Beacon", value: beacon.shortDescription)
                LabeledContent("Status", value: model.inRoom ? "In range" : "Out of range")
            }
            Button(model.beacon == nil ? "Add beacon…" : "Change beacon…") { editingBeacon = true }
                .disabled(model.isLocked)
        } header: {
            Text("Bedroom beacon")
        } footer: {
            Text("Leaving takes about 30 seconds to register. If it still says “In range” after you step out of the room, turn the beacon's transmit power down.")
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
