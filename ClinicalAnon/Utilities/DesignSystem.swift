//
//  DesignSystem.swift
//  ClinicalAnon
//
//  Purpose: Centralized design system with brand colors, typography, spacing, and styles
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Design System

struct DesignSystem {

    // MARK: - Colors

    struct Colors {

        // MARK: Primary Colors

        /// Primary Teal - Professional, trustworthy (#0A6B7C)
        static let primaryTeal = Color(red: 10/255, green: 107/255, blue: 124/255)

        /// Sage - Calm, clinical (#A9C1B5)
        static let sage = Color(red: 169/255, green: 193/255, blue: 181/255)

        /// Orange - Energy, action (#E68A2E)
        static let orange = Color(red: 230/255, green: 138/255, blue: 46/255)

        /// Sand - Warmth (#E8D4BC)
        static let sand = Color(red: 232/255, green: 212/255, blue: 188/255)

        /// Sand Dark - Deeper warmth (#D4AE80)
        static let sandDark = Color(red: 212/255, green: 174/255, blue: 128/255)

        /// Charcoal - Text, contrast (#2E2E2E)
        static let charcoal = Color(red: 46/255, green: 46/255, blue: 46/255)

        /// Warm White - Backgrounds (#FAF7F4)
        static let warmWhite = Color(red: 250/255, green: 247/255, blue: 244/255)

        // MARK: Semantic Colors

        /// Background color (adapts to light/dark mode)
        static let background = Color(
            light: warmWhite,
            dark: Color(red: 28/255, green: 28/255, blue: 30/255)
        )

        /// Surface color for cards and panels
        static let surface = Color(
            light: .white,
            dark: Color(red: 44/255, green: 44/255, blue: 46/255)
        )

        /// Text primary color
        static let textPrimary = Color(
            light: charcoal,
            dark: Color(red: 242/255, green: 242/255, blue: 247/255)
        )

        /// Text secondary color (lower contrast)
        static let textSecondary = Color(
            light: Color(red: 60/255, green: 60/255, blue: 67/255, opacity: 0.6),
            dark: Color(red: 235/255, green: 235/255, blue: 245/255, opacity: 0.6)
        )

        /// Border color
        static let border = Color(
            light: charcoal.opacity(0.2),
            dark: Color.white.opacity(0.1)
        )

        // MARK: Status Colors

        /// Success state - green
        static let success = Color.green

        /// Error state - red
        static let error = Color.red

        /// Warning state - orange
        static let warning = orange

        /// Processing/info state - teal
        static let info = primaryTeal

        // MARK: Highlight Colors (Entity Types)

        /// Person/Name highlight - Light blue
        static let highlightPerson = Color(red: 173/255, green: 216/255, blue: 230/255, opacity: 0.5)  // Light blue

        /// Organization highlight - Light purple/lavender
        static let highlightOrganization = Color(red: 221/255, green: 160/255, blue: 221/255, opacity: 0.5)  // Plum

        /// Date highlight - Light green
        static let highlightDate = Color(red: 144/255, green: 238/255, blue: 144/255, opacity: 0.5)  // Light green

        /// Location highlight - Light orange/peach
        static let highlightLocation = Color(red: 255/255, green: 218/255, blue: 185/255, opacity: 0.5)  // Peach

        /// Contact (email/phone) highlight - Light pink
        static let highlightContact = Color(red: 255/255, green: 182/255, blue: 193/255, opacity: 0.5)  // Light pink

        /// Identifier (IDs) highlight - Light gray
        static let highlightIdentifier = Color(red: 211/255, green: 211/255, blue: 211/255, opacity: 0.5)  // Light gray

        /// Yellow highlight for entities (30% opacity) - deprecated, use type-specific colors
        static let highlightYellow = Color.yellow.opacity(0.3)

        /// Teal highlight for read-only state
        static let highlightTeal = primaryTeal.opacity(0.1)
    }

    // MARK: - Typography

    struct Typography {

        // MARK: Font Names

        /// Lora font family (serif - for headings)
        private static let loraRegular = "Lora-Regular"
        private static let loraBold = "Lora-Bold"
        private static let loraItalic = "Lora-Italic"

        /// Source Sans 3 font family (sans-serif - for body)
        private static let sourceSansRegular = "SourceSans3-Regular"
        private static let sourceSansSemiBold = "SourceSans3-SemiBold"
        private static let sourceSansBold = "SourceSans3-Bold"

        // MARK: Font Styles

        /// Title style - Large serif heading (Lora Bold, 32pt)
        static let title: Font = .custom(loraBold, size: 32)

        /// Heading style - Medium serif heading (Lora Bold, 24pt)
        static let heading: Font = .custom(loraBold, size: 24)

        /// Subheading style - Small serif heading (Lora SemiBold, 18pt)
        static let subheading: Font = .custom(loraBold, size: 18)

        /// Body style - Regular body text (Source Sans 3, 16pt)
        static let body: Font = .custom(sourceSansRegular, size: 16)

        /// Body bold - Bold body text (Source Sans 3 SemiBold, 16pt)
        static let bodyBold: Font = .custom(sourceSansSemiBold, size: 16)

        /// Caption style - Small text (Source Sans 3, 14pt)
        static let caption: Font = .custom(sourceSansRegular, size: 14)

        /// Button style - Button text (Source Sans 3 SemiBold, 16pt)
        static let button: Font = .custom(sourceSansSemiBold, size: 16)

        /// Monospace - For clinical notes (SF Mono, 14pt)
        static let monospace: Font = .system(size: 14, design: .monospaced)

        /// Monospace large - For larger clinical text (SF Mono, 15pt)
        static let monospaceLarge: Font = .system(size: 15, design: .monospaced)

        // MARK: Text Styles (with color)

        /// Apply title text style
        static func titleStyle() -> some View {
            return EmptyView()
                .font(title)
                .foregroundColor(Colors.textPrimary)
        }

        /// Apply heading text style
        static func headingStyle() -> some View {
            return EmptyView()
                .font(heading)
                .foregroundColor(Colors.textPrimary)
        }

        /// Apply body text style
        static func bodyStyle() -> some View {
            return EmptyView()
                .font(body)
                .foregroundColor(Colors.textPrimary)
        }

        /// Apply caption text style
        static func captionStyle() -> some View {
            return EmptyView()
                .font(caption)
                .foregroundColor(Colors.textSecondary)
        }
    }

    // MARK: - Spacing

    struct Spacing {
        static let xs: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xlarge: CGFloat = 32
        static let xxlarge: CGFloat = 48
    }

    // MARK: - Corner Radius

    struct CornerRadius {
        /// Small radius - for compact elements (6px)
        static let small: CGFloat = 6       // Updated from 4px for modern macOS Sequoia style
        /// Medium radius - for buttons and cards (10px)
        static let medium: CGFloat = 10     // Updated from 8px for softer appearance
        /// Large radius - for primary buttons (14px)
        static let large: CGFloat = 14      // Updated from 12px for more rounded feel
        /// Extra large radius - for panels (20px)
        static let xlarge: CGFloat = 20     // Updated from 16px for major UI elements
        /// Extra extra large radius - for modals (24px)
        static let xxlarge: CGFloat = 24    // New value for maximum roundness
    }

    // MARK: - Shadows

    struct Shadow {

        /// Soft shadow for subtle elevation
        static let soft = ShadowStyle(
            color: Color.black.opacity(0.1),
            radius: 4,
            x: 0,
            y: 2
        )

        /// Medium shadow for cards
        static let medium = ShadowStyle(
            color: Color.black.opacity(0.15),
            radius: 8,
            x: 0,
            y: 4
        )

        /// Strong shadow for modals and overlays
        static let strong = ShadowStyle(
            color: Color.black.opacity(0.2),
            radius: 16,
            x: 0,
            y: 8
        )

        struct ShadowStyle {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }

    // MARK: - Elevation (Visual Hierarchy)

    struct Elevation {
        /// Recessed - for input/editable areas (slight inset appearance)
        static let recessed = ElevationStyle(
            backgroundOverlay: Color.black.opacity(0.02),
            shadowColor: Color.black.opacity(0.08),
            shadowRadius: 3,
            shadowX: 0,
            shadowY: 1,
            isInner: true
        )

        /// Base - for standard surfaces (no shadow)
        static let base = ElevationStyle(
            backgroundOverlay: Color.clear,
            shadowColor: Color.clear,
            shadowRadius: 0,
            shadowX: 0,
            shadowY: 0,
            isInner: false
        )

        /// Lifted - for result/output areas (subtle drop shadow)
        static let lifted = ElevationStyle(
            backgroundOverlay: Color.white.opacity(0.01),
            shadowColor: Color.black.opacity(0.06),
            shadowRadius: 8,
            shadowX: 0,
            shadowY: 2,
            isInner: false
        )

        struct ElevationStyle {
            let backgroundOverlay: Color
            let shadowColor: Color
            let shadowRadius: CGFloat
            let shadowX: CGFloat
            let shadowY: CGFloat
            let isInner: Bool
        }
    }

    // MARK: - Animation

    struct Animation {
        /// Quick animation for buttons and interactions (0.2s)
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.2)

        /// Standard animation for most UI changes (0.3s)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)

        /// Slow animation for major transitions (0.5s)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
    }
}

// MARK: - Color Extension for Light/Dark Mode

extension Color {
    init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(NSColor(name: nil) { appearance in
            switch appearance.name {
            case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        })
        #else
        self.init(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
        #endif
    }
}

// MARK: - View Extensions for Design System

extension View {

    /// Apply soft shadow
    func softShadow() -> some View {
        let shadow = DesignSystem.Shadow.soft
        return self.shadow(
            color: shadow.color,
            radius: shadow.radius,
            x: shadow.x,
            y: shadow.y
        )
    }

    /// Apply medium shadow
    func mediumShadow() -> some View {
        let shadow = DesignSystem.Shadow.medium
        return self.shadow(
            color: shadow.color,
            radius: shadow.radius,
            x: shadow.x,
            y: shadow.y
        )
    }

    /// Apply strong shadow
    func strongShadow() -> some View {
        let shadow = DesignSystem.Shadow.strong
        return self.shadow(
            color: shadow.color,
            radius: shadow.radius,
            x: shadow.x,
            y: shadow.y
        )
    }

    /// Apply card styling (surface color, medium corner radius, medium shadow)
    func cardStyle() -> some View {
        self
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .mediumShadow()
    }

    /// Apply recessed elevation (for input areas)
    func recessedElevation() -> some View {
        let elevation = DesignSystem.Elevation.recessed
        return self
            .background(
                DesignSystem.Colors.surface
                    .overlay(elevation.backgroundOverlay)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(Color.black.opacity(0.04), lineWidth: 1)
            )
    }

    /// Apply lifted elevation (for output/result areas)
    func liftedElevation() -> some View {
        let elevation = DesignSystem.Elevation.lifted
        return self
            .background(
                DesignSystem.Colors.surface
                    .overlay(elevation.backgroundOverlay)
            )
            .shadow(
                color: elevation.shadowColor,
                radius: elevation.shadowRadius,
                x: elevation.shadowX,
                y: elevation.shadowY
            )
    }

    /// Apply base elevation (no shadow, standard surface)
    func baseElevation() -> some View {
        self.background(DesignSystem.Colors.surface)
    }
}

// MARK: - Preview Helper

#if DEBUG
struct DesignSystem_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            // Title
            Text("ClinicalAnon")
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.primaryTeal)

            // Heading
            Text("Privacy-first clinical text anonymization")
                .font(DesignSystem.Typography.heading)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            // Body text
            Text("This application helps practitioners anonymize clinical notes while preserving therapeutic meaning.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)

            // Color swatches
            HStack(spacing: DesignSystem.Spacing.medium) {
                ColorSwatch(color: DesignSystem.Colors.primaryTeal, name: "Teal")
                ColorSwatch(color: DesignSystem.Colors.sage, name: "Sage")
                ColorSwatch(color: DesignSystem.Colors.orange, name: "Orange")
                ColorSwatch(color: DesignSystem.Colors.sand, name: "Sand")
            }

            // Card example
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("Card Component")
                    .font(DesignSystem.Typography.subheading)
                Text("This is how a card looks with our design system")
                    .font(DesignSystem.Typography.caption)
            }
            .padding(DesignSystem.Spacing.medium)
            .cardStyle()
        }
        .padding(DesignSystem.Spacing.xlarge)
        .frame(width: 600)
    }

    struct ColorSwatch: View {
        let color: Color
        let name: String

        var body: some View {
            VStack(spacing: DesignSystem.Spacing.xs) {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(color)
                    .frame(width: 60, height: 60)
                Text(name)
                    .font(DesignSystem.Typography.caption)
            }
        }
    }
}
#endif
