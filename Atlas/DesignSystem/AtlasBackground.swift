import SwiftUI

enum BackgroundTheme {
    case home
    case workout
    case friends
    case stats
    case auth
    case neutral
}

private struct BackgroundThemeKey: EnvironmentKey {
    static let defaultValue: BackgroundTheme = .neutral
}

extension EnvironmentValues {
    var atlasBackgroundTheme: BackgroundTheme {
        get { self[BackgroundThemeKey.self] }
        set { self[BackgroundThemeKey.self] = newValue }
    }
}

struct AtlasBackground: ViewModifier {
    @Environment(\.atlasBackgroundTheme) private var theme

    var overrideTheme: BackgroundTheme?

    func body(content: Content) -> some View {
        content
            .background(gradient(for: overrideTheme ?? theme))
    }

    private func gradient(for theme: BackgroundTheme) -> some View {
        let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        let alphaDrop: Double = reduceTransparency ? 0.4 : 1.0

        let colors: [Color]
        switch theme {
        case .workout:
            colors = [
                Color(red: 55/255, green: 34/255, blue: 28/255).opacity(0.9 * alphaDrop),
                Color(red: 93/255, green: 51/255, blue: 33/255).opacity(0.75 * alphaDrop),
                Color(red: 15/255, green: 10/255, blue: 8/255).opacity(0.95 * alphaDrop)
            ]
        case .home:
            colors = [
                Color(red: 28/255, green: 28/255, blue: 30/255).opacity(0.96 * alphaDrop),
                Color(red: 46/255, green: 38/255, blue: 30/255).opacity(0.55 * alphaDrop),
                Color.black.opacity(0.94 * alphaDrop)
            ]
        case .friends:
            colors = [
                Color(red: 13/255, green: 25/255, blue: 35/255).opacity(0.95 * alphaDrop),
                Color(red: 20/255, green: 50/255, blue: 60/255).opacity(0.65 * alphaDrop),
                Color.black.opacity(0.92 * alphaDrop)
            ]
        case .stats:
            // "Old money" green gradient - muted, luxury palette
            colors = [
                Color(red: 11/255, green: 42/255, blue: 30/255).opacity(0.96 * alphaDrop),  // Deep forest
                Color(red: 18/255, green: 53/255, blue: 36/255).opacity(0.65 * alphaDrop),  // Bottle green
                Color(red: 14/255, green: 15/255, blue: 16/255).opacity(0.92 * alphaDrop)   // Warm charcoal
            ]
        case .auth:
            colors = [
                Color(red: 24/255, green: 22/255, blue: 24/255).opacity(0.96 * alphaDrop),
                Color(red: 46/255, green: 34/255, blue: 28/255).opacity(0.55 * alphaDrop),
                Color.black.opacity(0.92 * alphaDrop)
            ]
        case .neutral:
            colors = [
                Color.black.opacity(0.96 * alphaDrop),
                Color.black.opacity(0.92 * alphaDrop)
            ]
        }

        let baseGradient = LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let vignette = RadialGradient(
            colors: [
                Color.black.opacity(0.0),
                Color.black.opacity(0.15 * alphaDrop),
                Color.black.opacity(0.35 * alphaDrop)
            ],
            center: .center,
            startRadius: 60,
            endRadius: 500
        )

        return ZStack {
            baseGradient
            vignette
        }
        .ignoresSafeArea()
    }
}

extension View {
    func atlasBackground(_ theme: BackgroundTheme? = nil) -> some View {
        modifier(AtlasBackground(overrideTheme: theme))
    }

    func atlasBackgroundTheme(_ theme: BackgroundTheme) -> some View {
        environment(\.atlasBackgroundTheme, theme)
    }
}
