import SwiftUI

enum AppLinks {
    static let privacyPolicy = URL(string: "https://github.com/namarks/goodnight-phone/blob/main/PRIVACY.md")!
}

/// First-launch walkthrough: what Goodnight Phone does and what it will ask for.
/// Permissions themselves are requested from the setup checklist afterwards.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "moon.zzz.fill",
            title: "Put the phone down at bedtime",
            text: "Goodnight Phone blocks the apps you choose while your iPhone is in the bedroom during bedtime hours. Walk out of the room and they unlock. There's nothing to tap."
        ),
        OnboardingPage(
            icon: "dot.radiowaves.left.and.right",
            title: "Mark the bedroom",
            text: "Put a small Bluetooth beacon by the bed (about $20 online), or use a spare iPad or iPhone running Goodnight Phone. Your iPhone notices when it's near."
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            title: "Private, and hard to skip",
            text: "Goodnight Phone needs Screen Time access to block apps and Location so iOS can wake it when you walk in. Nothing leaves your phone. While apps are blocked, settings lock too. In an emergency, turn Goodnight Phone off in Settings → Screen Time."
        ),
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pages[index].tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                Button {
                    if isLastPage {
                        onFinish()
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    Text(isLastPage ? "Set up Goodnight Phone" : "Next")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Link("Privacy policy", destination: AppLinks.privacyPolicy)
                    .font(.footnote)
                    .opacity(isLastPage ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.12, blue: 0.36), Color(red: 0.03, green: 0.04, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .environment(\.colorScheme, .dark)
    }
}

private struct OnboardingPage: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32)
    }
}
