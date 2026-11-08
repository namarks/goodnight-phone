import SwiftUI

/// "Where to put the beacon": illustrated tips for placing it where switching it off takes effort.
/// Read-only, so it stays open to read while apps are blocked. Art source: docs/art/guide-scenes.py.
struct BeaconPlacementGuide: View {
    private struct Tip: Identifiable {
        let art: String
        let title: String
        let text: String
        var id: String { art }
    }

    private let tips = [
        Tip(
            art: "GuideHardware",
            title: "What you're placing",
            text: "The USB beacon (Blue Charm BC-U1) is a tiny black plug, smaller than a quarter. It goes into any USB wall charger, so the charger is the part you'll see. The battery beacon (BC05) is a white puck about two inches across."
        ),
        Tip(
            art: "GuideNightstand",
            title: "Not on the nightstand",
            text: "If you can reach it from bed, unplugging it at midnight takes two seconds. Skip the outlet by your pillow and the top of the nightstand."
        ),
        Tip(
            art: "GuideUnderBed",
            title: "Low, behind the bed",
            text: "Use the outlet behind the headboard or under the bed. With the charger and beacon down there, getting to them means crawling under or pulling the bed out, and the signal still fills the room."
        ),
        Tip(
            art: "GuideOutletCover",
            title: "Shut it in",
            text: "A childproof outlet box cover from a hardware store closes over the charger and the beacon together. Bluetooth goes right through the plastic, and sleepy fingers don't. A few strips of strong tape work too."
        ),
        Tip(
            art: "GuidePuck",
            title: "Battery beacon? Tape it underneath",
            text: "Stick the BC05 under the bed frame or inside the back of a drawer with two strips of strong tape. There's no cord to pull, and the coin cell lasts for years."
        ),
        Tip(
            art: "GuideFloorPlan",
            title: "Far from the door",
            text: "Put it on the side of the room away from the door, not on the wall beside it, so the bedroom ends at the doorway. Then step out into the hallway with Goodnight Phone open. If Status still says “In the bedroom” after 30 seconds, tap Shorter."
        ),
        Tip(
            art: "GuideHub",
            title: "Using a spare iPad or iPhone",
            text: "Stand it on a dresser with Goodnight Phone open and Broadcast on, plugged into an outlet that's awkward to reach. Then set the boundary standing in the bedroom doorway. A hub board can hide behind furniture the same way."
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Goodnight Phone only knows whether the beacon is near. Put it where switching it off takes real effort, so putting the phone down is the easy choice.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Brand.ink.opacity(0.85))

                ForEach(tips) { tip in
                    VStack(alignment: .leading, spacing: 10) {
                        Image(tip.art)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 290)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Brand.fixedInk, lineWidth: 3))
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                            .padding(.bottom, 6)
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
