import SwiftUI
import UIKit

/// The picture-book look: nursery green, blanket red, moon yellow and night-window blue on
/// paper, with soft serif headings. Colors live in Assets.xcassets (most have a dark variant);
/// the heading font is bundled in App/Fonts and registered through UIAppFonts in project.yml.
enum Brand {
    static let green = Color.accentColor
    static let red = Color("Blanket")
    static let yellow = Color("Moon")
    static let night = Color("Night")
    static let paper = Color("Paper")
    static let card = Color("Card")
    static let ink = Color("Ink")
    /// Ink and cream are fixed (not adaptive) where the background is fixed too.
    static let fixedInk = Color(red: 0x23 / 255, green: 0x30 / 255, blue: 0x2A / 255)
    static let cream = Color(red: 0xF7 / 255, green: 0xEF / 255, blue: 0xDD / 255)

    /// Fraunces at its softest (SOFT 100, opsz 48, weight 650), cut to one static font.
    static let headingFontName = "FrauncesSoft-SemiBold"

    /// Soft serif for titles. Scales with Dynamic Type.
    static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(headingFontName, size: size, relativeTo: style)
    }

    /// Navigation bar titles in the heading font and green, set once at launch.
    static func styleNavigationBars() {
        let green = UIColor(named: "AccentColor") ?? .systemGreen
        let appearance = UINavigationBar.appearance()
        if let large = UIFont(name: headingFontName, size: 34) {
            appearance.largeTitleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large),
                .foregroundColor: green,
            ]
        }
        if let inline = UIFont(name: headingFontName, size: 18) {
            appearance.titleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline),
                .foregroundColor: green,
            ]
        }
    }
}

extension View {
    /// Paper background behind a Form, with card-colored rows (rows set their own via brandRow()).
    func brandForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Brand.paper.ignoresSafeArea())
    }

    /// Card-colored row background, so rows sit on the paper like cards.
    func brandRow() -> some View {
        listRowBackground(Brand.card)
    }
}

/// A Form section header in the heading font, green, not uppercased.
struct BrandHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Brand.heading(19, relativeTo: .headline))
            .foregroundStyle(Brand.green)
            .textCase(nil)
    }
}

/// The big red "storybook" button: ink outline and a solid offset shadow, like a printed page.
struct BrandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.title3, design: .rounded).weight(.heavy))
            .foregroundStyle(Brand.cream)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(Brand.red))
            .overlay(Capsule().strokeBorder(Brand.fixedInk, lineWidth: 3))
            .background(Capsule().fill(Brand.fixedInk).offset(x: configuration.isPressed ? 1 : 4, y: configuration.isPressed ? 1 : 4))
            .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
            .opacity(isEnabled ? 1 : 0.5)
    }
}
