import SwiftUI

enum AppLinks {
    static let privacyPolicy = URL(string: "https://goodnightphone.marks-labs.com/privacy")!
    /// The website's "Choose a beacon" page: the bedroom hub's parts first, then the Blue Charm
    /// beacons. It holds the tagged Amazon links, so the app itself never links to Amazon
    /// (Associates links in apps need separate approval).
    static let chooseBeacon = URL(string: "https://goodnightphone.marks-labs.com/beacon")!
    /// The same page, scrolled to the bedroom hub's parts or to the Blue Charm.
    static let chooseHub = URL(string: "https://goodnightphone.marks-labs.com/beacon#hub")!
    static let chooseBlueCharm = URL(string: "https://goodnightphone.marks-labs.com/beacon#blue-charm")!
    /// One-click install of the bedroom hub firmware. Needs Chrome or Edge on a Mac or PC (Web
    /// Serial), so the app shares this link rather than opening it.
    static let hubInstall = URL(string: "https://goodnightphone.marks-labs.com/hub/install")!
}

/// First-launch walkthrough: what Goodnight Phone does and what it will ask for.
/// Permissions themselves are requested from the setup checklist afterwards.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            art: "BedroomScene",
            title: "Put the phone down at bedtime",
            text: "Goodnight Phone blocks the apps you choose while your iPhone is in the bedroom during bedtime hours. Walk out of the room and they unlock. There's nothing to tap."
        ),
        OnboardingPage(
            art: "BeaconScene",
            title: "Mark the bedroom",
            text: "Put a small Bluetooth beacon by the bed (about $20 online), or use a spare iPad or iPhone running Goodnight Phone. Your iPhone notices when it's near."
        ),
        OnboardingPage(
            art: "PrivacyScene",
            title: "Private, and hard to skip",
            text: "Goodnight Phone needs Screen Time access to block apps and Location so iOS can wake it when you walk in. Nothing leaves your phone. While apps are blocked, settings lock too. In an emergency, turn Goodnight Phone off in Settings → Screen Time."
        ),
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 20) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pages[index].tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 14) {
                PageDots(count: pages.count, current: page)

                Button {
                    if isLastPage {
                        onFinish()
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    Text(isLastPage ? "Set up Goodnight Phone" : "Next")
                }
                .buttonStyle(BrandButtonStyle())

                Link("Privacy policy", destination: AppLinks.privacyPolicy)
                    .font(.footnote.weight(.bold))
                    .tint(Brand.green)
                    .opacity(isLastPage ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: ReadableWidth.max)
        .frame(maxWidth: .infinity)
        .background(Brand.paper.ignoresSafeArea())
    }
}

/// Three small dots under the pages; the current one is red.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Brand.red : Brand.ink.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

private struct OnboardingPage: View {
    let art: String
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(art)
                    .resizable()
                    .aspectRatio(390.0 / 470.0, contentMode: .fit)
                    .frame(maxHeight: 380)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Brand.fixedInk, lineWidth: 3))
                    .accessibilityHidden(true)
                    .padding(.bottom, 10)
                Text(title)
                    .font(Brand.heading(32))
                    .foregroundStyle(Brand.green)
                Text(text)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Brand.ink.opacity(0.85))
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
