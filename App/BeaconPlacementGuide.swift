import SwiftUI

/// "Where to put the beacon": illustrated tips for placing it where switching it off takes effort.
/// Read-only, so it stays open to read while apps are blocked. Art source: docs/art/guide-scenes.py.
struct BeaconPlacementGuide: View {
    private struct Tip: Identifiable {
        /// nil for a text-only tip, so only the main ideas get a picture.
        var art: String?
        let title: String
        let text: String
        var id: String { title }
    }

    private let tips = [
        Tip(
            art: "GuideHardware",
            title: "Pick a beacon",
            text: "USB beacon: a tiny plug that goes into any USB wall charger, so it never needs a battery.\nBattery beacon: a small puck you can stick anywhere. The battery lasts for years."
        ),
        Tip(
            art: "GuideNightstand",
            title: "Keep it out of reach",
            text: "Not on the nightstand or by your pillow. If you can reach it from bed, you'll unplug it."
        ),
        Tip(
            art: "GuideUnderBed",
            title: "USB: plug it in under the bed",
            text: "Use an outlet behind or under the bed, so unplugging it means crawling under."
        ),
        Tip(
            title: "Want it even harder to reach?",
            text: "Put a childproof cover over the outlet. The signal goes right through it."
        ),
        Tip(
            art: "GuidePuck",
            title: "Battery: stick it under the bed",
            text: "Use a Command strip to stick the puck to the wall behind the bed or under the bed frame. There's no cord to pull, and it peels off cleanly when the battery needs changing."
        ),
        Tip(
            art: "GuideFloorPlan",
            title: "Keep it away from the door",
            text: "Put it on the far side of the room, so the signal stops at the doorway. Then step into the hallway. If Goodnight Phone still says “In the bedroom” after 30 seconds, tap Shorter."
        ),
        Tip(
            title: "Using a spare iPad or iPhone instead?",
            text: "Leave it plugged in on a dresser with Broadcast on. Then set the boundary standing in the bedroom doorway."
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Hide the beacon somewhere hard to reach, so you can't just unplug it at bedtime.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Brand.ink.opacity(0.85))

                ForEach(tips) { tip in
                    VStack(alignment: .leading, spacing: 10) {
                        if let art = tip.art {
                            Image(art)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 290)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Brand.fixedInk, lineWidth: 3))
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                                .padding(.bottom, 6)
                        }
                        Text(tip.title)
                            .font(Brand.heading(26))
                            .foregroundStyle(Brand.green)
                            .accessibilityAddTraits(.isHeader)
                        Text(tip.text)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Brand.ink.opacity(0.85))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: ReadableWidth.max)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.paper.ignoresSafeArea())
        .navigationTitle("Where to put it")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { BeaconPlacementGuide() }
}
