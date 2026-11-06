import SwiftUI

/// Widest a column of settings or text gets. Wider screens (the iPhone Duo's inner screen) center it.
enum ReadableWidth {
    static let max: CGFloat = 600
}

extension View {
    /// Centers a Form's rows in a column no wider than `ReadableWidth.max`, keeping the grouped
    /// background and scroll indicators at the screen edges. No effect on phone-width screens.
    func readableWidth() -> some View {
        modifier(ReadableWidthModifier())
    }
}

private struct ReadableWidthModifier: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        Group {
            // Any contentMargins, even 0, replaces the Form's default inset, so phone widths get none.
            if width > ReadableWidth.max {
                content.contentMargins(.horizontal, (width - ReadableWidth.max) / 2, for: .scrollContent)
            } else {
                content
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
            }
        }
    }
}
