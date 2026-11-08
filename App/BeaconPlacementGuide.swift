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
            title: "What you're placing",
            text: "The USB beacon is a tiny black plug, smaller than a quarter. It goes into a USB wall charger. The battery beacon is a white puck about 2 inches wide."
        ),
        Tip(
            art: "GuideNightstand",
            title: "Not on the nightstand",
            text: "If you can reach it from bed, it's too easy to unplug."
        ),
        Tip(
            art: "GuideUnderBed",
            title: "Down behind the bed",
            text: "Plug the charger into an outlet behind or under the bed. To unplug it, you'd have to crawl under."
        ),
        Tip(
            title: "Make it even harder",
            text: "Put a childproof outlet cover over the charger, or tape it in. Bluetooth works right through."
        ),
        Tip(
            art: "GuidePuck",
            title: "Battery beacon? Tape it under the bed",
            text: "Tape the puck to the bed frame. There's no cord to pull, and the battery lasts for years."
        ),
        Tip(
            art: "GuideFloorPlan",
            title: "Far from the door",
            text: "Keep it on the far side of the room from the door. Then walk into the hallway with Goodnight Phone open. If it still says “In the bedroom” after 30 seconds, tap Shorter."
        ),
        Tip(
            title: "Using a spare iPad or iPhone?",
            text: "Keep it on a dresser, plugged in, with Broadcast on. Set the boundary standing in the bedroom doorway."
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Put the beacon somewhere that's a hassle to reach, so switching it off at midnight takes real effort.")
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
