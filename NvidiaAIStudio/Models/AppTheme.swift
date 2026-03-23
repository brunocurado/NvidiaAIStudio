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
        backgroundTint: Color(red: 0.05, green: 0.07, blue: 0.12),
        sidebarTint: Color(red: 0.06, green: 0.08, blue: 0.14),
        accentColor: Color(red: 0.0, green: 0.75, blue: 1.0),
        codeBackground: Color.black.opacity(0.4)
    )

    static let light = AppTheme(
        id: "light",
        name: "Light",
        icon: "sun.max.fill",
        colorScheme: .light,
        backgroundTint: Color(red: 0.93, green: 0.93, blue: 0.97),
        sidebarTint: Color(red: 0.90, green: 0.90, blue: 0.95),
        accentColor: .blue,
        codeBackground: Color(red: 0.95, green: 0.95, blue: 0.95)
    )

    static let system = AppTheme(
        id: "system",
        name: "System",
        icon: "circle.lefthalf.filled",
        colorScheme: nil,
        backgroundTint: Color(nsColor: .windowBackgroundColor),
        sidebarTint: Color(nsColor: .controlBackgroundColor),
        accentColor: .blue,
        codeBackground: Color(nsColor: .textBackgroundColor)
    )

    /// Catppuccin Mocha — popular warm-dark developer theme
    static let catppuccin = AppTheme(
        id: "catppuccin",
        name: "Catppuccin",
        icon: "cup.and.saucer.fill",
        colorScheme: .dark,
        backgroundTint: Color(red: 0.118, green: 0.110, blue: 0.165),  // #1e1e2a crust
        sidebarTint:    Color(red: 0.137, green: 0.129, blue: 0.188),  // #23213030 mantle
        accentColor:    Color(red: 0.533, green: 0.490, blue: 0.918),  // mauve
        codeBackground: Color(red: 0.094, green: 0.086, blue: 0.137)   // #181825 base
    )

    /// Nord — arctic, north-bluish clean theme
    static let nord = AppTheme(
        id: "nord",
        name: "Nord",
        icon: "snowflake",
        colorScheme: .dark,
        backgroundTint: Color(red: 0.180, green: 0.204, blue: 0.251),  // #2e3440
        sidebarTint:    Color(red: 0.208, green: 0.231, blue: 0.278),  // #353a47
        accentColor:    Color(red: 0.529, green: 0.753, blue: 0.847),  // #88c0d8 frost
        codeBackground: Color(red: 0.145, green: 0.165, blue: 0.204)   // #252a33
    )

    /// Solarized Dark — classic retro developer theme
    static let solarizedDark = AppTheme(
        id: "solarized_dark",
        name: "Solarized Dark",
        icon: "sun.horizon.fill",
        colorScheme: .dark,
        backgroundTint: Color(red: 0.000, green: 0.169, blue: 0.212),  // #002b36 base03
        sidebarTint:    Color(red: 0.027, green: 0.212, blue: 0.259),  // #073642 base02
        accentColor:    Color(red: 0.149, green: 0.545, blue: 0.824),  // #2690d2 blue
        codeBackground: Color(red: 0.000, green: 0.129, blue: 0.161)   // #002129
    )

    /// Solarized Light
    static let solarizedLight = AppTheme(
        id: "solarized_light",
        name: "Solarized Light",
        icon: "sun.max.circle.fill",
        colorScheme: .light,
        backgroundTint: Color(red: 0.992, green: 0.965, blue: 0.890),  // #fdf6e3 base3
        sidebarTint:    Color(red: 0.933, green: 0.910, blue: 0.835),  // #eee8d5 base2
        accentColor:    Color(red: 0.149, green: 0.545, blue: 0.824),  // blue
        codeBackground: Color(red: 0.933, green: 0.910, blue: 0.835)
    )

    /// Dracula — a dark theme for the night owls
    static let dracula = AppTheme(
        id: "dracula",
        name: "Dracula",
        icon: "bolt.fill",
        colorScheme: .dark,
        backgroundTint: Color(red: 0.157, green: 0.165, blue: 0.212),  // #282a36
        sidebarTint:    Color(red: 0.235, green: 0.247, blue: 0.314),  // #3c3f50
        accentColor:    Color(red: 0.741, green: 0.576, blue: 1.000),  // #bd93f9 purple
        codeBackground: Color(red: 0.118, green: 0.122, blue: 0.157)   // #1e1f28
    )

    /// Tokyo Night
    static let tokyoNight = AppTheme(
        id: "tokyo_night",
        name: "Tokyo Night",
        icon: "building.2.fill",
        colorScheme: .dark,
        backgroundTint: Color(red: 0.102, green: 0.110, blue: 0.173),  // #1a1c2c
        sidebarTint:    Color(red: 0.118, green: 0.133, blue: 0.208),  // #1e2235
        accentColor:    Color(red: 0.471, green: 0.663, blue: 1.000),  // #78a9ff
        codeBackground: Color(red: 0.071, green: 0.078, blue: 0.122)   // #12141f
    )

    /// All available themes
    static let all: [AppTheme] = [
        .dark, .light, .system,
        .catppuccin, .nord,
        .solarizedDark, .solarizedLight,
        .dracula, .tokyoNight
    ]

    static func find(id: String) -> AppTheme {
        all.first { $0.id == id } ?? .dark
    }
}
