import SwiftUI

// MARK: - Adaptive Color Extension

extension Color {
    /// Creates a color that automatically adapts between light and dark appearances.
    /// Uses NSColor's dynamic provider so it responds to system appearance changes
    /// without needing @Environment(\.colorScheme).
    /// Named `lightMode:darkMode:` to avoid ambiguity with macOS 26's native `Color(light:dark:)`.
    init(lightMode: Color, darkMode: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(darkMode) : NSColor(lightMode)
        })
    }
}

// MARK: - Glass Theme Tokens

/// Centralized design tokens for the Liquid Glass aesthetic.
/// All colors are adaptive — they automatically switch between light and dark values.
struct GlassTheme {
    
    // MARK: Typography Colors
    
    /// Primary text — titles, headings, main readouts
    static let textPrimary = Color(lightMode: .black.opacity(0.92), darkMode: .white.opacity(0.95))
    
    /// Secondary text — labels, captions, descriptions
    static let textSecondary = Color(lightMode: .black.opacity(0.65), darkMode: .white.opacity(0.72))
    
    /// Muted text — hints, timestamps, hashes, legal text
    static let textMuted = Color(lightMode: .black.opacity(0.42), darkMode: .white.opacity(0.48))
    
    // MARK: Glass Material Tints
    
    /// General panel glass tint
    static let panelTint = Color(lightMode: .white.opacity(0.08), darkMode: .black.opacity(0.32))
    
    /// Sidebar glass tint
    static let sidebarTint = Color(lightMode: .white.opacity(0.09), darkMode: .black.opacity(0.36))
    
    /// Card/tile glass tint
    static let glassTileTint = Color(lightMode: .white.opacity(0.10), darkMode: .black.opacity(0.38))
    
    /// Stronger glass tint for emphasis
    static let glassTintStrong = Color(lightMode: .white.opacity(0.12), darkMode: .black.opacity(0.42))
    
    /// Subtle canvas wash
    static let canvasTint = Color(lightMode: .black.opacity(0.03), darkMode: .white.opacity(0.03))
    
    /// Canvas sheen highlight
    static let canvasSheen = Color(lightMode: .white.opacity(0.04), darkMode: .white.opacity(0.06))
    
    // MARK: Semantic Status Colors
    
    static let green  = Color(red: 0.27, green: 0.86, blue: 0.43)
    static let red    = Color(red: 1.00, green: 0.36, blue: 0.36)
    static let orange = Color(red: 0.95, green: 0.58, blue: 0.23)
    static let yellow = Color(red: 0.95, green: 0.82, blue: 0.32)
    static let purple = Color(red: 0.58, green: 0.42, blue: 0.95)
    
    // MARK: Flat Fill (3rd nesting level)
    
    /// Use this instead of glass when you're at the 3rd nesting level.
    /// Prevents the washed-out white surface from triple glass stacking.
    static let flatFill = Color.primary.opacity(0.04)
    static let flatStroke = Color.primary.opacity(0.08)
    
    // MARK: Agent Status Colors (deduplicated)
    
    static func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "running", "executing":  return green
        case "thinking", "planning":  return purple
        case "waiting", "queued":     return orange
        case "completed", "done":     return Color(red: 0.30, green: 0.56, blue: 0.95)
        case "failed", "error":       return red
        default:                      return textMuted
        }
    }
}

// MARK: - Glass Canvas Backdrop (Anchor Layer)

/// The invisible sampling anchor for Liquid Glass refraction.
/// Place ONCE at the root of your view hierarchy (ContentView).
/// This establishes the material context that all glass lenses refract through.
///
/// Architecture: anchor → lens → (flat fill at 3rd level)
struct GlassCanvasBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Color.clear
            .glassEffect(colorScheme == .dark ? .regular : .clear, in: Rectangle())
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

// MARK: - Glass Modifiers

extension View {
    
    /// Sidebar rail — glass background for the sidebar panel.
    /// Tinted with `GlassTheme.sidebarTint` so it adapts between light and dark mode.
    func macSidebarRail(in shape: RoundedRectangle = RoundedRectangle(cornerRadius: 26, style: .continuous)) -> some View {
        self.glassEffect(.clear.tint(GlassTheme.sidebarTint), in: shape)
    }

    /// Navigation glass — toolbars, navigation surfaces.
    /// Tinted with `GlassTheme.panelTint` so it adapts between light and dark mode.
    func macNavigationGlass(in shape: some Shape = RoundedRectangle(cornerRadius: 20, style: .continuous)) -> some View {
        self.glassEffect(.clear.tint(GlassTheme.panelTint), in: shape)
    }

    /// Content board — cards, lists, tables. The workhorse modifier.
    /// Multiple shape overloads for flexibility.
    /// Tinted with `GlassTheme.panelTint` so it adapts between light and dark mode.
    func macContentBoard(cornerRadius: CGFloat = 16) -> some View {
        self.macContentBoard(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func macContentBoard(in shape: RoundedRectangle) -> some View {
        self.glassEffect(.clear.tint(GlassTheme.panelTint), in: shape)
    }

    func macContentBoard(in shape: Capsule) -> some View {
        self.glassEffect(.clear.tint(GlassTheme.panelTint).interactive(), in: Capsule())
    }

    func macContentBoard(in shape: Circle) -> some View {
        self.glassEffect(.clear.tint(GlassTheme.panelTint).interactive(), in: Circle())
    }

    /// Glass tile — standalone widget tiles with larger corner radius.
    /// Tinted with `GlassTheme.glassTileTint` so it adapts between light and dark mode.
    func macGlassTile(cornerRadius: CGFloat = 24) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self.glassEffect(.clear.tint(GlassTheme.glassTileTint), in: shape)
    }

    /// Modal glass — for ZStack overlay popovers (NOT .sheet!).
    /// `.sheet` on macOS opens a separate NSWindow with opaque backdrop that kills glass.
    /// Tinted with `GlassTheme.glassTintStrong` (slightly more emphasis than a regular tile)
    /// so modals stand out and adapt between light and dark mode.
    func macModalGlass(cornerRadius: CGFloat = 32) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self.glassEffect(.clear.tint(GlassTheme.glassTintStrong).interactive(), in: shape)
            .shadow(color: .black.opacity(0.28), radius: 40, y: 20)
    }
    
    /// Control pill — filter pills with selection state.
    /// DO NOT wrap a row of pills in .macContentBoard — that creates glass-on-glass frost.
    func macControlPill(isSelected: Bool, accentColor: Color = .blue, cornerRadius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self.glassEffect(
            isSelected
                ? .clear.tint(accentColor.opacity(0.28)).interactive()
                : .clear.interactive(),
            in: shape
        )
    }
    
    /// Status glow — subtle shadow for active status indicators.
    func statusGlow(color: Color, active: Bool = true) -> some View {
        self.shadow(color: active ? color.opacity(0.5) : .clear, radius: 8)
    }
    
    /// Flat tile background — for the 3rd nesting level where glass would wash out.
    func flatTileBackground(cornerRadius: CGFloat = 22) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(GlassTheme.flatFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(GlassTheme.flatStroke, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Reusable Components

/// Interactive glass capsule button with hover effects.
/// Use ONLY on the canvas or directly on a glass surface.
/// Inside a tile/modal (3rd level), use a flat tinted capsule instead.
struct GlassButton: View {
    let title: String
    let icon: String?
    let accentColor: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    init(_ title: String, icon: String? = nil, accent: Color = .blue, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.accentColor = accent
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isHovered ? .primary : accentColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassEffect(
                isHovered
                    ? .clear.tint(accentColor.opacity(0.18)).interactive()
                    : .clear.interactive(),
                in: Capsule()
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Universal glass card container.
/// Wraps content with padding and a glass content board.
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content
    
    init(cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(16)
            .macContentBoard(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Subtle glass-aware divider.
struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
    }
}

/// Consistent section header.
struct GlassSectionHeader: View {
    let title: String
    let icon: String?
    
    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GlassTheme.textMuted)
            }
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(GlassTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

/// Close (X) button — always flat, never glass.
struct GlassCloseButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

/// Glass medallion for brand logos and icons.
struct GlassMedallion: View {
    let icon: String
    let size: CGFloat
    let accentColor: Color
    
    init(_ icon: String, size: CGFloat = 60, accent: Color = .blue) {
        self.icon = icon
        self.size = size
        self.accentColor = accent
    }
    
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.43, weight: .heavy))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(LinearGradient(
                colors: [accentColor, GlassTheme.purple.opacity(0.9)],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(width: size, height: size)
            .glassEffect(.clear.tint(accentColor.opacity(0.20)).interactive(), in: Circle())
            .shadow(color: accentColor.opacity(0.32), radius: 18, y: 8)
    }
}

// MARK: - Inline Button (for 3rd nesting level)

/// Use this INSTEAD of GlassButton when the button lives inside
/// another glass surface (tile, card, modal). Prevents glass-on-glass frost.
struct InlineTintedButton: View {
    let title: String
    let icon: String?
    let accentColor: Color
    let action: () -> Void
    
    init(_ title: String, icon: String? = nil, accent: Color = .blue, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.accentColor = accent
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(accentColor.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}
