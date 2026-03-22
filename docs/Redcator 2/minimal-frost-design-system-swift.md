# Redactor — SwiftUI Design System
**Version 1.0 · Minimal Frost · 3 Big Things Limited**
For use by AI coders and developers implementing the Redactor macOS app in SwiftUI / Xcode.

---

## 1. Design Philosophy

**Direction:** Minimal Frost
**Tagline:** "Glass panels on a gradient sky"
**Personality:** Clean · Precise · Light · Professional

The UI should feel like frosted glass cards floating on a soft gradient canvas. Cool, minimal, and spacious. No warmth, no sand tones, no coastal metaphors. Slate greys for text hierarchy, white glass for surfaces, cool gradient for depth. Clinicians should feel focused and uncluttered.

**Core principles:**
- Glass over flat — every surface uses white opacity + backdrop blur
- Cool over warm — slate palette, no beige or sand
- Gradient background — fixed multicolour gradient (indigo → blue → cyan → green), never flat
- Typography does the work — Sora geometric sans, weight hierarchy, no decorative elements
- Restraint — colour only for status and actions, not decoration

---

## 2. Colour Tokens

All colours defined as Swift `Color` extensions. Light/dark mode via `Color(light:dark:)`.

### 2.1 Setup

```swift
extension Color {
    // Slate palette
    static let kSlate900  = Color(hex: "#0f172a")   // Primary text, dark accents
    static let kSlate700  = Color(hex: "#334155")   // Secondary text
    static let kSlate500  = Color(hex: "#64748b")   // Muted text, labels
    static let kSlate400  = Color(hex: "#94a3b8")   // Placeholder, meta info
    static let kSlate200  = Color(hex: "#e2e8f0")   // Borders, dividers
    static let kSlate100  = Color(hex: "#f1f5f9")   // Subtle backgrounds
    static let kSlate50   = Color(hex: "#f8fafc")   // Page background alt

    // Glass
    static let kGlass75   = Color.white.opacity(0.75)  // Primary glass card
    static let kGlass60   = Color.white.opacity(0.60)  // Secondary glass card
    static let kGlass80   = Color.white.opacity(0.80)  // Buttons, detail cards

    // Status
    static let kSuccess   = Color(hex: "#22c55e")
    static let kWarning   = Color(hex: "#f59e0b")
    static let kError     = Color(hex: "#ef4444")
    static let kInfo      = Color(hex: "#0288d1")

    // Gradient stops (for page background)
    static let kGradStart = Color(hex: "#e0e7ff")   // Indigo tint
    static let kGradMid1  = Color(hex: "#dbeafe")   // Blue tint
    static let kGradMid2  = Color(hex: "#e0f2fe")   // Cyan tint
    static let kGradMid3  = Color(hex: "#d1fae5")   // Green tint
    static let kGradEnd   = Color(hex: "#ecfdf5")   // Emerald tint
}
```

### 2.2 Dark Mode Overrides

```swift
extension Color {
    static let kBgPrimary   = Color(light: .white, dark: Color(hex: "#0f172a"))
    static let kTextPrimary = Color(light: Color(hex: "#0f172a"), dark: Color(hex: "#f1f5f9"))
    static let kTextMuted   = Color(light: Color(hex: "#64748b"), dark: Color(hex: "#94a3b8"))
    static let kBorder      = Color(light: Color.black.opacity(0.04), dark: Color.white.opacity(0.08))
    static let kDivider     = Color(light: Color.black.opacity(0.06), dark: Color.white.opacity(0.06))

    // Glass in dark mode
    static let kGlassBg     = Color(light: Color.white.opacity(0.75), dark: Color.white.opacity(0.06))
    static let kGlassBorder = Color(light: Color.black.opacity(0.04), dark: Color.white.opacity(0.08))
}
```

### 2.3 Semantic Colour Roles

```swift
extension Color {
    // Entity highlights (for redaction UI)
    static let kHighlightPerson       = Color(light: Color(hex: "#dbeafe").opacity(0.6), dark: Color(hex: "#3b82f6").opacity(0.2))
    static let kHighlightOrganization = Color(light: Color(hex: "#e9d5ff").opacity(0.6), dark: Color(hex: "#a855f7").opacity(0.2))
    static let kHighlightDate         = Color(light: Color(hex: "#d1fae5").opacity(0.6), dark: Color(hex: "#22c55e").opacity(0.2))
    static let kHighlightLocation     = Color(light: Color(hex: "#ffedd5").opacity(0.6), dark: Color(hex: "#f97316").opacity(0.2))
    static let kHighlightContact      = Color(light: Color(hex: "#fce7f3").opacity(0.6), dark: Color(hex: "#ec4899").opacity(0.2))
    static let kHighlightIdentifier   = Color(light: Color(hex: "#f1f5f9").opacity(0.6), dark: Color(hex: "#64748b").opacity(0.2))

    // Session/recording
    static let kLiveIndicator = Color(hex: "#22c55e")
    static let kDestructive   = Color(light: Color(hex: "#ef4444"), dark: Color(hex: "#f87171"))
}
```

---

## 3. Typography

### 3.1 Font Setup

Add **Sora** to the Xcode project:
1. Download from Google Fonts: Sora in weights 300, 400, 500, 600, 700
2. Add `.ttf` files to the project target under `Resources/Fonts/`
3. Register in Info.plist under `ATSApplicationFontsPath: Fonts`

Required font files:
- `Sora-Light.ttf` (300)
- `Sora-Regular.ttf` (400)
- `Sora-Medium.ttf` (500)
- `Sora-SemiBold.ttf` (600)
- `Sora-Bold.ttf` (700)

### 3.2 Font Extension

```swift
extension Font {
    // Display — large page titles
    static let kDisplay = Font.custom("Sora-Bold", size: 28)

    // Headings
    static let kH1 = Font.custom("Sora-Bold", size: 22)
    static let kH2 = Font.custom("Sora-SemiBold", size: 18)
    static let kH3 = Font.custom("Sora-SemiBold", size: 16)

    // Body
    static let kBody     = Font.custom("Sora-Regular", size: 14)
    static let kBodyLg   = Font.custom("Sora-Regular", size: 15)
    static let kBodyMed  = Font.custom("Sora-Medium", size: 14)
    static let kBodySm   = Font.custom("Sora-Regular", size: 13)

    // Labels — pair with .textCase(.uppercase) and .tracking(0.5)
    static let kLabel    = Font.custom("Sora-SemiBold", size: 12)

    // Captions
    static let kCaption  = Font.custom("Sora-Regular", size: 12)

    // Table headers — pair with .textCase(.uppercase) and .tracking(0.5)
    static let kTableHeader = Font.custom("Sora-SemiBold", size: 11)

    // Buttons
    static let kButton   = Font.custom("Sora-SemiBold", size: 14)
    static let kButtonSm = Font.custom("Sora-SemiBold", size: 13)

    // Metrics / large numbers
    static let kMetricLg = Font.custom("Sora-Bold", size: 42)
    static let kMetricMd = Font.custom("Sora-Bold", size: 32)
    static let kMetricSm = Font.custom("Sora-Bold", size: 24)

    // Monospace — redacted markers, codes
    static let kMono     = Font.system(size: 12, design: .monospaced)
}
```

### 3.3 Typography Rules

```swift
// Section labels — ALWAYS uppercase + tracked
Text("SESSIONS")
    .font(.kLabel)
    .textCase(.uppercase)
    .tracking(0.5)
    .foregroundColor(.kSlate500)

// Table headers — same treatment
Text("CLIENT")
    .font(.kTableHeader)
    .textCase(.uppercase)
    .tracking(0.5)
    .foregroundColor(.kSlate500)

// Never use system font as primary typeface
// Never use .bold() modifier — use explicit font weight variants
// Body text colour: .kSlate700 (not .kSlate900)
// Headings colour: .kSlate900
```

---

## 4. Glass Panel System

### 4.1 GlassPanel ViewModifier

```swift
struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var blur: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.kGlassBg)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.kGlassBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.04), radius: 24, x: 0, y: 2)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }

    func glassPanelSm() -> some View {
        modifier(GlassPanelModifier(cornerRadius: 16, blur: 12))
    }

    func glassPanelXs() -> some View {
        modifier(GlassPanelModifier(cornerRadius: 10, blur: 10))
    }
}

// Usage
VStack { /* content */ }
    .padding(.spLG)
    .glassPanel()
```

### 4.2 Gradient Background

```swift
struct GradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            Color(hex: "#0f172a")
                .ignoresSafeArea()
        } else {
            ZStack {
                LinearGradient(
                    colors: [.kGradStart, .kGradMid1, .kGradMid2, .kGradMid3, .kGradEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Decorative blur — indigo pool top-right
                RadialGradient(
                    colors: [Color(hex: "#6366f1").opacity(0.12), .clear],
                    center: .init(x: 0.85, y: 0.05),
                    startRadius: 0,
                    endRadius: 300
                )

                // Decorative blur — green pool bottom-left
                RadialGradient(
                    colors: [Color(hex: "#10b981").opacity(0.10), .clear],
                    center: .init(x: 0.10, y: 0.92),
                    startRadius: 0,
                    endRadius: 250
                )
            }
            .ignoresSafeArea()
        }
    }
}

// In app shell — ALWAYS at root:
ZStack {
    GradientBackground()
    // glass panels on top
}
```

---

## 5. App Shell Layout

```swift
struct AppShell: View {
    var body: some View {
        ZStack {
            GradientBackground()

            HStack(spacing: .spMD) {
                Sidebar()
                    .frame(width: 220)
                    .padding(.spLG)
                    .glassPanel()

                MainContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.spLG)
                    .glassPanel()
            }
            .padding(.spMD)
        }
        .frame(minWidth: 800, minHeight: 520)
    }
}
```

---

## 6. Spacing Tokens

```swift
extension CGFloat {
    static let spXS:  CGFloat = 4
    static let spSM:  CGFloat = 8
    static let spMD:  CGFloat = 12
    static let spLG:  CGFloat = 16
    static let spXL:  CGFloat = 20
    static let sp2XL: CGFloat = 24
    static let sp3XL: CGFloat = 28
    static let sp4XL: CGFloat = 32
    static let sp5XL: CGFloat = 40
    static let sp6XL: CGFloat = 48
}

// Usage
HStack(spacing: .spMD) { ... }
.padding(.spLG)
```

---

## 7. Border Radius

```swift
extension CGFloat {
    static let rXS:  CGFloat = 6
    static let rSM:  CGFloat = 8
    static let rMD:  CGFloat = 10
    static let rLG:  CGFloat = 12
    static let rXL:  CGFloat = 14
    static let r2XL: CGFloat = 16
    static let r3XL: CGFloat = 20
    static let rFull: CGFloat = 9999
}
```

---

## 8. Shadows

```swift
extension View {
    func shadowGlass() -> some View {
        self.shadow(color: .black.opacity(0.04), radius: 24, x: 0, y: 2)
    }

    func shadowGlassSm() -> some View {
        self.shadow(color: .black.opacity(0.03), radius: 12, x: 0, y: 1)
    }

    func shadowButton() -> some View {
        self.shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
    }
}
```

---

## 9. Component Implementations

### 9.1 Buttons

```swift
struct KPrimaryButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.kButton)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: .rLG)
                        .fill(Color.kSlate900)
                        .shadowButton()
                )
        }
        .buttonStyle(.plain)
    }
}

struct KSecondaryButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.kButton)
                .foregroundColor(.kSlate700)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: .rLG)
                        .fill(Color.kGlass80)
                        .overlay(
                            RoundedRectangle(cornerRadius: .rLG)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

struct KDestructiveButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.kButtonSm)
                .foregroundColor(.kDestructive)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: .rMD)
                        .fill(Color.kError.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: .rMD)
                                .stroke(Color.kError.opacity(0.22), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
```

### 9.2 Text Input

```swift
struct KTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.kBody)
            .foregroundColor(.kTextPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: .rMD)
                    .fill(Color.kGlassBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: .rMD)
                            .stroke(Color.kGlassBorder, lineWidth: 1)
                    )
            )
            .textFieldStyle(.plain)
    }
}
```

### 9.3 Status Indicators

```swift
struct StatusDot: View {
    enum Status { case ready, hold, done, failed }
    let status: Status

    private var color: Color {
        switch status {
        case .ready:  return .kSuccess
        case .hold:   return .kWarning
        case .done:   return .kSlate900
        case .failed: return .kError
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }
}
```

### 9.4 Section Label

```swift
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.kLabel)
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundColor(.kSlate500)
    }
}
```

### 9.5 Avatar / Initials Circle

```swift
struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: .rMD)
                .fill(
                    LinearGradient(
                        colors: [Color.kSlate200, Color(hex: "#cbd5e1")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            Text(initials)
                .font(.custom("Sora-SemiBold", size: size * 0.325))
                .foregroundColor(.kSlate700)
        }
    }
}
```

---

## 10. Redaction UI

```swift
struct RedactedToken: View {
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.kSlate200)
            .frame(width: width, height: 14)
            .help("Redacted — de-identified before AI processing")
    }
}

struct PrivacyBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .light))
                .foregroundColor(.kSlate500)

            Text("De-identified")
                .font(.kCaption)
                .fontWeight(.semibold)
                .foregroundColor(.kSlate500)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: .rXS)
                .fill(Color.kSlate100)
                .overlay(
                    RoundedRectangle(cornerRadius: .rXS)
                        .stroke(Color.kSlate200, lineWidth: 0.5)
                )
        )
    }
}
```

---

## 11. Icons

Use **SF Symbols** with `.light` or `.thin` weight. Never heavy/bold icons.

```swift
enum KIconSize {
    case nav        // 20pt
    case inline     // 16pt
    case status     // 12pt

    var size: CGFloat {
        switch self {
        case .nav:    return 20
        case .inline: return 16
        case .status: return 12
        }
    }
}

// Usage — always .light weight
Image(systemName: "lock.fill")
    .font(.system(size: KIconSize.inline.size, weight: .light))
    .foregroundColor(.kSlate500)

// Large decorative icons — .thin weight
Image(systemName: "shield.checkered")
    .font(.system(size: 48, weight: .thin))
    .foregroundColor(.kSlate400)
```

---

## 12. Animation

```swift
extension Animation {
    static let kFast    = Animation.easeInOut(duration: 0.15)
    static let kDefault = Animation.easeInOut(duration: 0.20)
    static let kSlow    = Animation.easeOut(duration: 0.30)
    static let kMetric  = Animation.easeOut(duration: 0.60)
}

// Respect system reduce motion
@Environment(\.accessibilityReduceMotion) var reduceMotion

withAnimation(reduceMotion ? .none : .kDefault) {
    // state change
}

// Rules:
// No bounce easing
// No animation on text content
// Interactive transitions: max 0.2s
// Data visualisation: 0.6s ease-out on mount only
```

---

## 13. macOS Window Configuration

```swift
@main
struct RedactorApp: App {
    var body: some Scene {
        Window("Redactor", id: "main") {
            AppShell()
        }
        .defaultSize(width: 1000, height: 700)
    }
}
```

---

## 14. Do Not

```
❌ Warm colours (beige, sand, orange) as structural elements
❌ Color.black or #000000 in the UI — use .kSlate900 maximum
❌ .font(.system(...)) as primary typeface — always Sora
❌ Flat opaque backgrounds — everything is glass or gradient
❌ Serif fonts anywhere — Sora only
❌ .bold() modifier — use explicit font weight variants
❌ Emoji as icons — use SF Symbols
❌ Heavy/bold icon weights — use .light or .thin
❌ Decorative colour — colour is for status and actions only
❌ cornerRadius > 20 on panels (pills/badges: rFull is fine)
❌ Animations on text content
❌ Gradient as card fill — gradients are for page background only
```

---

## 15. Quick Reference Card

```
Font:         Sora (all weights 300-700)
Text:         .kSlate900 (headings) · .kSlate700 (body) · .kSlate500 (muted)
Glass:        .glassPanel() / .glassPanelSm() / .glassPanelXs()
Background:   GradientBackground() — ALWAYS at root
Spacing:      .spXS(4) .spSM(8) .spMD(12) .spLG(16) .spXL(20) .sp2XL(24)
Radius:       .rXS(6) .rSM(8) .rMD(10) .rLG(12) .rXL(14) .r2XL(16) .r3XL(20)
Icons:        SF Symbols, .light/.thin weight, KIconSize enum
Animation:    .kFast(0.15s) .kDefault(0.2s) .kSlow(0.3s) .kMetric(0.6s)
Status:       .kSuccess(green) .kWarning(amber) .kError(red)
Buttons:      KPrimaryButton (slate900) · KSecondaryButton (glass) · KDestructiveButton (red)
Dark mode:    kBgPrimary/kTextPrimary/kGlassBg adapt automatically
```
