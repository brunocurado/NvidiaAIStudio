import SwiftUI

/// All available colour themes for the app.
/// Each theme defines a background tint, sidebar tint, accent colour,
/// and whether to force dark/light colour scheme.
struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let colorScheme: ColorScheme?      // nil = follow system
    let backgroundTint: Color          // main window dark overlay
    let sidebarTint: Color             // sidebar material tint
    let accentColor: Color             // blue highlights, buttons
    let codeBackground: Color          // code block background

    static func == (lhs: AppTheme, rhs: AppTheme) -> Bool { lhs.id == rhs.id }

    // MARK: - Built-in themes

    static let dark = AppTheme(
        id: "dark",
        name: "Dark",
        icon: "moon.fill",
        colorScheme: .dark,
        backgroundTint: Color(red: 0.05, green: 0.07, blue: 0.12).opacity(0.3),
        sidebarTint: .clear,
        accentColor: Color(red: 0.0, green: 0.75, blue: 1.0),
        codeBackground: Color.black.opacity(0.4)
    )

    static let lightsOut = AppTheme(
        id: "lights_out",
        name: "Lights Out",
        icon: "moon.stars.fill",
        colorScheme: .dark,
        backgroundTint: Color.black.opacity(0.4),
        sidebarTint: .clear,
        accentColor: .white,
        codeBackground: Color(red: 0.05, green: 0.05, blue: 0.05)
    )

    static let light = AppTheme(
        id: "light",
        name: "Light",
        icon: "sun.max.fill",
        colorScheme: .light,
        backgroundTint: Color.white.opacity(0.15),
        sidebarTint: .clear,
        accentColor: .blue,
        codeBackground: Color(red: 0.95, green: 0.95, blue: 0.95)
    )

    static let system = AppTheme(
        id: "system",
        name: "System",
        icon: "circle.lefthalf.filled",
        colorScheme: nil,
        backgroundTint: .clear,
        sidebarTint: .clear,
        accentColor: .blue,
        codeBackground: Color(nsColor: .textBackgroundColor)
    )

    /// Catppuccin Mocha — popular warm-dark developer theme
    static let catppuccin = AppTheme(
        id: "catppuccin",
        name: "Catppuccin",
        icon: "cup.and.saucer.fill",
        colorScheme: .dark,
        backgroundTint: Color(red: 0.118, green: 0.110, blue: 0.165).opacity(0.3),  // #1e1e2a crust
        sidebarTint:    .clear,
        accentColor:    Color(red: 0.533, green: 0.490, blue: 0.918),  // mauve
        codeBackground: Color(red: 0.094, green: 0.086, blue: 0.137)   // #181825 base
    )

    /// Nord — arctic, north-bluish clean theme
    static let nord = AppTheme(
        id: "nord",
        name: "Nord",
        icon: "snowflake",
        colorScheme: .dark,
        backgroundTint: Color(red: 0.180, green: 0.204, blue: 0.251).opacity(0.3),  // #2e3440
        sidebarTint:    .clear,
        accentColor:    Color(red: 0.529, green: 0.753, blue: 0.847),  // #88c0d8 frost
        codeBackground: Color(red: 0.145, green: 0.165, blue: 0.204)   // #252a33
    )

    /// Solarized Dark — classic retro developer theme
    static let solarizedDark = AppTheme(
        id: "solarized_dark",
        name: "Solarized Dark",
        icon: "sun.horizon.fill",
        colorScheme: .dark,
        backgroundTint: Color(red: 0.000, green: 0.169, blue: 0.212).opacity(0.3),  // #002b36 base03
        sidebarTint:    .clear,
        accentColor:    Color(red: 0.149, green: 0.545, blue: 0.824),  // #2690d2 blue
        codeBackground: Color(red: 0.000, green: 0.129, blue: 0.161)   // #002129
    )

    /// Solarized Light
    static let solarizedLight = AppTheme(
        id: "solarized_light",
        name: "Solarized Light",
        icon: "sun.max.circle.fill",
        colorScheme: .light,
        backgroundTint: Color(red: 0.992, green: 0.965, blue: 0.890).opacity(0.15),  // #fdf6e3 base3
        sidebarTint:    .clear,
        accentColor:    Color(red: 0.149, green: 0.545, blue: 0.824),  // blue
        codeBackground: Color(red: 0.933, green: 0.910, blue: 0.835)
    )

    /// Dracula — a dark theme for the night owls
    static let dracula = AppTheme(
        id: "dracula",
        name: "Dracula",
        icon: "bolt.fill",
        colorScheme: .dark,
        backgroundTint: Color(red: 0.157, green: 0.165, blue: 0.212).opacity(0.3),  // #282a36
        sidebarTint:    .clear,
        accentColor:    Color(red: 0.741, green: 0.576, blue: 1.000),  // #bd93f9 purple
        codeBackground: Color(red: 0.118, green: 0.122, blue: 0.157)   // #1e1f28
    )

    /// Tokyo Night
    static let tokyoNight = AppTheme(
        id: "tokyo_night",
        name: "Tokyo Night",
        icon: "building.2.fill",
        colorScheme: .dark,
        backgroundTint: Color(red: 0.102, green: 0.110, blue: 0.173).opacity(0.3),  // #1a1c2c
        sidebarTint:    .clear,
        accentColor:    Color(red: 0.471, green: 0.663, blue: 1.000),  // #78a9ff
        codeBackground: Color(red: 0.071, green: 0.078, blue: 0.122)   // #12141f
    )

    /// Liquid Glass — premium glass-first theme (light)
    static let liquid_glass_light = AppTheme(
        id: "liquid_glass_light",
        name: "Liquid Glass",
        icon: "drop.fill",
        colorScheme: .light,
        backgroundTint: .clear,
        sidebarTint: .clear,
        accentColor: Color(red: 0.30, green: 0.56, blue: 0.95),
        codeBackground: Color.primary.opacity(0.04)
    )

    /// Liquid Glass Dark — premium glass-first theme (dark)
    static let liquid_glass_dark = AppTheme(
        id: "liquid_glass_dark",
        name: "Liquid Glass Dark",
        icon: "drop.fill",
        colorScheme: .dark,
        backgroundTint: .clear,
        sidebarTint: .clear,
        accentColor: Color(red: 0.30, green: 0.56, blue: 0.95),
        codeBackground: Color.primary.opacity(0.04)
    )

    /// All available themes
    static let all: [AppTheme] = [
        .liquid_glass_light, .liquid_glass_dark,
        .dark, .lightsOut, .light, .system,
        .catppuccin, .nord,
        .solarizedDark, .solarizedLight,
        .dracula, .tokyoNight
    ]

    static func find(id: String) -> AppTheme {
        all.first { $0.id == id } ?? .liquid_glass_dark
    }
}
