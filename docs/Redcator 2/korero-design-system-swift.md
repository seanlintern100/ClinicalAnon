# Kōrero — SwiftUI Design System
**Version 1.0 · 3 Big Things Limited**
For use by AI coders and developers implementing the Kōrero macOS app in SwiftUI / Xcode.

---

## 1. Design Philosophy

**Direction:** Coastal Laboratory
**Tagline:** "Clinical clarity meets the Pacific edge"
**Personality:** Precise · Grounded · Coastal · Methodical

The UI should feel like a well-made scientific instrument found on an Aotearoa coastline — precise, trustworthy, and texturally alive. Not sterile. Not corporate. Glass surfaces sit over warm sand-and-teal substrates. Every panel has depth through translucency and specular sheen. Clinicians should feel calm and focused.

**Core principles:**
- Warmth over sterility — sand and teal, never cold grey
- Glass over flat — every panel uses `.ultraThinMaterial` or layered opacity
- Restraint over noise — colour carries meaning, not decoration
- Teal dominates (30%), sand supports (secondary), blue glass accents sparingly
- 60% neutral substrate, 30% teal, 10% accent (sand / sea glass)

---

## 2. Xcode Asset Catalog — Colour Tokens

Create all colours in `Assets.xcassets` with **Any Appearance** (light) and **Dark** variants. Use these exact names throughout the codebase.

### 2.1 Setup

```swift
// Extension for convenient access
extension Color {
    // Backgrounds
    static let kBgPrimary      = Color("kBgPrimary")
    static let kBgSurface      = Color("kBgSurface")

    // Teal family
    static let kTealPrimary    = Color("kTealPrimary")
    static let kTealMid        = Color("kTealMid")
    static let kTealLight      = Color("kTealLight")

    // Sand family
    static let kSandAccent     = Color("kSandAccent")
    static let kSandLight      = Color("kSandLight")

    // Sea glass family
    static let kSeaGlass       = Color("kSeaGlass")
    static let kSeaGlassLight  = Color("kSeaGlassLight")

    // Text
    static let kTextPrimary    = Color("kTextPrimary")
    static let kTextMuted      = Color("kTextMuted")
    static let kTextInverse    = Color("kTextInverse")

    // Glass
    static let kGlassFill      = Color("kGlassFill")
    static let kGlassBorder    = Color("kGlassBorder")
    static let kGlassSheen     = Color("kGlassSheen")
}
```

### 2.2 Asset Values

| Token name | Any (Light) | Dark |
|---|---|---|
| `kBgPrimary` | `#F2EDE4` | `#0D1F1C` |
| `kBgSurface` | `#EAE4D8` | `#122420` |
| `kTealPrimary` | `#2C5F5A` | `#3DBFAA` |
| `kTealMid` | `#3D7A74` | `#2A8F7A` |
| `kTealLight` | `#7FB8B2` | `#6DDAC4` |
| `kSandAccent` | `#C49860` | `#D4A860` |
| `kSandLight` | `#E0C898` | `#EAC88A` |
| `kSeaGlass` | `#7BA4B8` | `#7DC4D8` |
| `kSeaGlassLight` | `#A8C8D8` | `#A8DDE8` |
| `kTextPrimary` | `#1E3230` | `#D8F0EC` |
| `kTextMuted` | `#6B7B78` | `#6AADA0` |
| `kTextInverse` | `#FFFFFF` | `#0D1F1C` |
| `kGlassFill` | `#FFFFFF` at 52% opacity | `#FFFFFF` at 6% opacity |
| `kGlassBorder` | `#FFFFFF` at 80% opacity | `#64C8B4` at 18% opacity |
| `kGlassSheen` | `#FFFFFF` at 85% opacity | `#78DCC8` at 10% opacity |

> **Note:** `kGlassFill`, `kGlassBorder`, `kGlassSheen` — set these as colour assets with the alpha baked in, or use `Color.white.opacity(0.52)` etc. inline.

### 2.3 Semantic Colour Roles

```swift
extension Color {
    // Conversation
    static let kClinicianBubble = kTealPrimary.opacity(0.18)
    static let kClientBubble    = kSeaGlass.opacity(0.18)

    // Metric bars
    static let kMetricAlliance  = kTealPrimary
    static let kMetricPacing    = kSeaGlass
    static let kMetricAffect    = kSandAccent
    static let kMetricEngagement = kTealLight

    // Status
    static let kLiveIndicator   = kSandAccent
    static let kDestructive     = Color(hex: "#C0392B")  // light
    // Dark destructive: Color(hex: "#E07070")
}

// Convenience hex init
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
```

---

## 3. Typography

### 3.1 Font Setup

Add **Lora** and **Source Sans 3** to the Xcode project:
1. Download from Google Fonts
2. Add `.ttf` files to the project target
3. Register in `Info.plist` under `UIAppFonts` (or `ATSApplicationFontsPath` for macOS)

Required font files:
- `Lora-Medium.ttf` (500)
- `Lora-SemiBold.ttf` (600)
- `Lora-Bold.ttf` (700)
- `Lora-MediumItalic.ttf` (500 italic)
- `SourceSans3-Regular.ttf` (400)
- `SourceSans3-Medium.ttf` (500)
- `SourceSans3-SemiBold.ttf` (600)

### 3.2 Font Extension

```swift
extension Font {
    // Display — Lora, used for session titles, report headers
    static let kDisplay = Font.custom("Lora-SemiBold", size: 28)

    // Headings
    static let kH1 = Font.custom("Lora-SemiBold", size: 22)
    static let kH2 = Font.custom("Lora-Medium", size: 18)      // always kTealPrimary colour
    static let kH3 = Font.custom("SourceSans3-SemiBold", size: 15)

    // Body
    static let kBody     = Font.custom("SourceSans3-Regular", size: 13)
    static let kBodyMed  = Font.custom("SourceSans3-Medium", size: 13)

    // Labels — pair with .textCase(.uppercase) and .tracking(0.9)
    static let kLabel    = Font.custom("SourceSans3-SemiBold", size: 11)

    // Captions
    static let kCaption  = Font.custom("SourceSans3-Regular", size: 10)

    // Monospace — redacted markers, codes
    static let kMono     = Font.system(size: 11, design: .monospaced)

    // Italic variants
    static let kH2Italic = Font.custom("Lora-MediumItalic", size: 18)
    static let kBodyItalic = Font.custom("Lora-MediumItalic", size: 13)
}
```

### 3.3 Typography Rules

```swift
// H2 section headers — ALWAYS kTealPrimary
Text("Session Notes")
    .font(.kH2)
    .foregroundColor(.kTealPrimary)

// Section labels — ALWAYS uppercase + tracked
Text("SESSIONS")
    .font(.kLabel)
    .textCase(.uppercase)
    .tracking(0.9)          // 0.08em × 11px ≈ 0.9pt
    .foregroundColor(.kTextMuted)

// Italic session titles
Text("Session · Client 0042")
    .font(.kH2Italic)
    .foregroundColor(.kTextPrimary)

// Never use system font as primary typeface
// Never use .bold() modifier — use explicit font weight variants
// Max line length for body text blocks: 72 characters
```

---

## 4. Glass Panel System

### 4.1 GlassPanel ViewModifier

```swift
struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var sheenHeight: CGFloat = 32

    func body(content: Content) -> some View {
        content
            .background(
                ZStack(alignment: .top) {
                    // Base glass fill
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                    // Fallback for older macOS
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.kGlassFill)
                    // Specular sheen — top edge only
                    VStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.kGlassSheen)
                            .frame(height: sheenHeight)
                            .opacity(0.4)
                        Spacer()
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.kGlassBorder, lineWidth: 0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 12, sheenHeight: CGFloat = 32) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, sheenHeight: sheenHeight))
    }

    func glassPanelSm() -> some View {
        modifier(GlassPanelModifier(cornerRadius: 8, sheenHeight: 14))
    }
}

// Usage
VStack { /* content */ }
    .padding(16)
    .glassPanel()

// Small variant (waveform, metrics bar)
HStack { /* content */ }
    .padding(.horizontal, 12)
    .glassPanelSm()
```

### 4.2 Accent Stripe Modifier

```swift
enum AccentRole {
    case teal, sand, seaGlass

    var color: Color {
        switch self {
        case .teal:     return .kTealPrimary
        case .sand:     return .kSandAccent
        case .seaGlass: return .kSeaGlass
        }
    }

    var opacity: Double {
        switch self {
        case .teal:     return 0.55
        case .sand:     return 0.60
        case .seaGlass: return 0.50
        }
    }
}

struct AccentStripeModifier: ViewModifier {
    let role: AccentRole

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(role.color.opacity(role.opacity))
                .frame(width: 3)
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension View {
    func accentStripe(_ role: AccentRole) -> some View {
        modifier(AccentStripeModifier(role: role))
    }
}

// Usage:
// Teal stripe → clinician / transcription context
// Sand stripe → insights, feedback, reports
// Sea glass stripe → client / audio / secondary data
VStack { /* content */ }
    .glassPanel()
    .accentStripe(.sand)
```

### 4.3 Ambient Background

```swift
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color.kBgPrimary

            // Top-right teal pool
            RadialGradient(
                colors: [Color.kTealPrimary.opacity(0.10), .clear],
                center: .init(x: 0.82, y: 0.14),
                startRadius: 0,
                endRadius: 200
            )

            // Bottom-left sea glass pool
            RadialGradient(
                colors: [Color.kSeaGlass.opacity(0.08), .clear],
                center: .init(x: 0.10, y: 0.88),
                startRadius: 0,
                endRadius: 150
            )

            // Bottom-right sand pool
            RadialGradient(
                colors: [Color.kSandAccent.opacity(0.09), .clear],
                center: .init(x: 0.92, y: 0.90),
                startRadius: 0,
                endRadius: 100
            )
        }
        .ignoresSafeArea()
    }
}

// In app shell:
ZStack {
    AmbientBackground()
    // content panels on top
}
```

---

## 5. App Shell Layout

```swift
struct AppShell: View {
    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                TopBar()                    // 44pt height

                HStack(spacing: 12) {
                    Sidebar()               // 172pt width
                        .frame(width: 172)

                    MainContentPanel()      // flex: 1
                        .frame(maxWidth: .infinity)
                }
                .padding(12)
            }
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
    static let spXL:  CGFloat = 24
    static let sp2XL: CGFloat = 32
    static let sp3XL: CGFloat = 48
}

// Usage
HStack(spacing: .spMD) { ... }
.padding(.spLG)
```

---

## 7. Component Implementations

### 7.1 Navigation Sidebar

```swift
struct Sidebar: View {
    @Binding var selectedSession: Session?
    @Binding var selectedTool: Tool?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo mark
            LogoMark()
                .padding(.bottom, .spXL)

            // Sessions section
            SidebarSectionLabel("SESSIONS")
            ForEach(sessions) { session in
                SidebarNavItem(session: session, isActive: selectedSession == session)
            }

            Spacer()

            // Tools section
            SidebarSectionLabel("TOOLS")
            ForEach(Tool.allCases) { tool in
                SidebarToolItem(tool: tool)
            }
        }
        .padding(.spLG)
        .frame(maxHeight: .infinity)
        .glassPanel()
    }
}

struct LogoMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.kTealPrimary.opacity(0.40))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.kTealPrimary.opacity(0.25), lineWidth: 1)
                )
            Text("K")
                .font(.kH2)
                .foregroundColor(.kTextInverse)
        }
        .frame(width: 34, height: 34)
    }
}

struct SidebarSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.kLabel)
            .textCase(.uppercase)
            .tracking(0.9)
            .foregroundColor(.kTextMuted)
            .padding(.top, .spXL)
            .padding(.bottom, .spSM)
    }
}

struct SidebarNavItem: View {
    let session: Session
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle)
                    .font(isActive ? .kBodyMed : .kBody)
                    .foregroundColor(isActive ? .kTealPrimary : .kTextPrimary)

                // Status pill
                RoundedRectangle(cornerRadius: 3)
                    .fill(isActive ? Color.kSandAccent.opacity(0.60)
                                   : Color.kTextMuted.opacity(0.25))
                    .frame(width: isActive ? 32 : 42, height: 8)
            }
            Spacer()
        }
        .padding(.horizontal, .spMD)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.kTealPrimary.opacity(0.22) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color.kTealPrimary.opacity(0.44) : .clear,
                                lineWidth: 0.5)
                )
        )
    }
}
```

### 7.2 Top Bar

```swift
struct TopBar: View {
    let sessionTitle: String
    let timestamp: String
    let isLive: Bool

    var body: some View {
        HStack {
            Text(sessionTitle)
                .font(.kH2Italic)
                .foregroundColor(.kTextPrimary)

            Spacer()

            if isLive {
                LiveBadge()
            }

            Text(timestamp)
                .font(.kCaption)
                .foregroundColor(.kTextMuted)
        }
        .padding(.horizontal, .spLG)
        .frame(height: 44)
        .glassPanel(cornerRadius: 10, sheenHeight: 44)
        .accentStripe(.teal)
    }
}

struct LiveBadge: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.kSandAccent)
                .frame(width: 8, height: 8)
                .scaleEffect(pulsing ? 1.3 : 1.0)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: pulsing
                )
                .onAppear { pulsing = true }

            Text("Live")
                .font(.kLabel)
                .foregroundColor(.kSandAccent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.kSandAccent.opacity(0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.kSandAccent.opacity(0.50), lineWidth: 0.75)
                )
        )
    }
}
```

### 7.3 Transcript Bubbles

```swift
struct TranscriptBubble: View {
    enum Speaker { case clinician, client }

    let text: String
    let speaker: Speaker

    private var isClient: Bool { speaker == .client }

    private var bubbleColor: Color {
        isClient ? .kSeaGlass : .kTealPrimary
    }

    var body: some View {
        VStack(alignment: isClient ? .trailing : .leading, spacing: 3) {
            Text(isClient ? "Client" : "Clinician")
                .font(.kCaption)
                .fontWeight(.bold)
                .foregroundColor(bubbleColor.opacity(0.9))

            Text(text)
                .font(.kBody)
                .foregroundColor(.kTextPrimary)
                .padding(10)
                .frame(maxWidth: 190, alignment: isClient ? .trailing : .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(bubbleColor.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(bubbleColor.opacity(0.35), lineWidth: 0.6)
                        )
                )
        }
        .frame(maxWidth: .infinity, alignment: isClient ? .trailing : .leading)
    }
}
```

### 7.4 Metrics Bar

```swift
struct MetricsBar: View {
    let alliance: Double    // 0–100
    let pacing: Double
    let affect: Double
    let engagement: Double

    var body: some View {
        HStack(spacing: 0) {
            MetricItem(label: "Alliance",    value: alliance,    color: .kTealPrimary)
            MetricItem(label: "Pacing",      value: pacing,      color: .kSeaGlass)
            MetricItem(label: "Affect",      value: affect,      color: .kSandAccent)
            MetricItem(label: "Engagement",  value: engagement,  color: .kTealLight)
        }
        .padding(.horizontal, .spMD)
        .frame(height: 50)
        .glassPanelSm()
        .accentStripe(.sand)
    }
}

struct MetricItem: View {
    let label: String
    let value: Double
    let color: Color

    @State private var animatedValue: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.kCaption)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundColor(.kTextMuted)

            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.kTextMuted.opacity(0.20))
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(color.opacity(0.85))
                            .frame(width: geo.size.width * (animatedValue / 100))
                    }
                }
                .frame(height: 5)

                Text("\(Int(value))")
                    .font(.kCaption)
                    .fontWeight(.medium)
                    .foregroundColor(color)
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animatedValue = value
            }
        }
    }
}
```

### 7.5 Alliance Ring

```swift
struct AllianceRing: View {
    let alliance: Double    // 0–100, outer ring
    let engagement: Double  // 0–100, inner ring

    @State private var animated = false

    var body: some View {
        ZStack {
            // Outer ring — teal (alliance)
            RingTrack(radius: 58, strokeWidth: 8, color: .kTealPrimary,
                      value: animated ? alliance / 100 : 0)

            // Inner ring — sea glass (engagement)
            RingTrack(radius: 44, strokeWidth: 5, color: .kSeaGlass,
                      value: animated ? engagement / 100 : 0)

            // Centre value
            VStack(spacing: 2) {
                Text("\(Int(alliance))")
                    .font(Font.custom("SourceSans3-Regular", size: 26))
                    .fontWeight(.light)
                    .foregroundColor(.kTealLight)

                Text("/ 100")
                    .font(.kCaption)
                    .foregroundColor(.kTextMuted)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animated = true
            }
        }
    }
}

struct RingTrack: View {
    let radius: CGFloat
    let strokeWidth: CGFloat
    let color: Color
    let value: Double   // 0.0–1.0

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(color.opacity(0.12), lineWidth: strokeWidth)
                .frame(width: radius * 2, height: radius * 2)

            // Fill
            Circle()
                .trim(from: 0, to: value)
                .stroke(color.opacity(0.9),
                        style: StrokeStyle(lineWidth: strokeWidth,
                                           lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)
                .rotationEffect(.degrees(-90))
        }
    }
}
```

### 7.6 Insight Panel

```swift
struct InsightRow {
    let role: AccentRole
    let category: String
    let message: String
}

struct InsightPanel: View {
    let title: String
    let insights: [InsightRow]

    var body: some View {
        VStack(alignment: .leading, spacing: .spSM) {
            Text(title)
                .font(.kBodyItalic)
                .foregroundColor(.kTextPrimary)

            ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(insight.role.color.opacity(0.70))
                        .frame(width: 6, height: 20)

                    HStack(spacing: 6) {
                        Text(insight.category)
                            .font(.kCaption)
                            .fontWeight(.semibold)
                            .foregroundColor(insight.role.color)

                        Text(insight.message)
                            .font(.kCaption)
                            .foregroundColor(.kTextMuted)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.spLG)
        .glassPanel(cornerRadius: 10)
        .accentStripe(.sand)
    }
}
```

### 7.7 Buttons

```swift
// Primary button
struct KPrimaryButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.kLabel)
                .foregroundColor(.kTextInverse)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.kTealPrimary)
                        .shadow(color: Color.kTealPrimary.opacity(0.30),
                                radius: 6, y: 3)
                )
        }
        .buttonStyle(.plain)
    }
}

// Secondary button
struct KSecondaryButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.kCaption)
                .foregroundColor(.kTextMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.kGlassFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.kGlassBorder, lineWidth: 0.75)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// Destructive button
struct KDestructiveButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.kCaption)
                .foregroundColor(Color(hex: "#F87171"))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.22), lineWidth: 0.75)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
```

### 7.8 Text Input

```swift
struct KTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.kBody)
            .foregroundColor(.kTextPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.kGlassFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.kGlassBorder, lineWidth: 0.75)
                    )
            )
            .textFieldStyle(.plain)
    }
}
```

---

## 8. Redaction UI

```swift
// Redacted text placeholder
struct RedactedToken: View {
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.kSandLight)
            .frame(width: width, height: 14)
            .help("Redacted — de-identified before AI processing")
    }
}

// Privacy badge
struct PrivacyBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundColor(.kTealPrimary)

            Text("De-identified")
                .font(.kCaption)
                .fontWeight(.semibold)
                .foregroundColor(.kTealPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.kTealPrimary.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.kTealPrimary.opacity(0.40), lineWidth: 0.5)
                )
        )
    }
}

// Processing shimmer (text being analysed)
struct ProcessingShimmer: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.kTealLight.opacity(0.4), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: phase * geo.size.width * 1.4 - geo.size.width * 0.4)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func processingShimmer() -> some View {
        modifier(ProcessingShimmer())
    }
}
```

---

## 9. Icons

Use **SF Symbols** as the primary icon system on macOS (available natively, no import needed).
Map to Phosphor Icons weight equivalents using SF Symbols `thin` or `light` weight.

```swift
// Standard icon sizing
enum KIconSize {
    case nav        // 20pt — sidebar tool icons
    case inline     // 16pt — inline UI actions
    case status     // 12pt — status indicators

    var size: CGFloat {
        switch self {
        case .nav:    return 20
        case .inline: return 16
        case .status: return 12
        }
    }
}

// Usage
Image(systemName: "lock.fill")
    .font(.system(size: KIconSize.inline.size, weight: .light))
    .foregroundColor(.kTextMuted)

// Icon colour rules:
// Default:  .kTextMuted
// Active:   role colour (teal / sand / sea glass per context)
// On teal:  .kTextInverse
// Never use emoji as icons in the app UI
```

### SF Symbol Mapping

| Role | SF Symbol |
|---|---|
| Privacy / lock | `lock.fill` / `lock.open.fill` |
| Recording live | `record.circle` |
| Session / transcript | `text.bubble` |
| Reports | `doc.text` |
| Insights | `chart.line.uptrend.xyaxis` |
| Settings | `gearshape` |
| Audio waveform | `waveform` |
| Export | `arrow.up.doc` |
| Redact | `eye.slash` |
| Clinician | `stethoscope` |
| Working alliance | `heart.text.square` |

---

## 10. Animation

```swift
// Standard transitions
extension Animation {
    static let kDefault    = Animation.easeInOut(duration: 0.20)
    static let kFast       = Animation.easeInOut(duration: 0.15)
    static let kPanel      = Animation.easeOut(duration: 0.25)
    static let kMetric     = Animation.easeOut(duration: 0.60)
    static let kRing       = Animation.easeOut(duration: 0.80)
}

// Panel appear transition
.transition(
    .opacity.combined(with: .offset(y: 4))
)
.animation(.kPanel, value: isVisible)

// Respect system reduce motion setting
@Environment(\.accessibilityReduceMotion) var reduceMotion

withAnimation(reduceMotion ? .none : .kMetric) {
    animatedValue = targetValue
}

// Rules:
// No bounce easing
// No animation on text content
// Interactive element transitions: max 0.2s
// Data visualisation (bars, rings): 0.6–0.8s ease-out on mount only
```

---

## 11. Accessibility

```swift
// Minimum tap target
.frame(minWidth: 44, minHeight: 44)

// Focus ring
.focusable()
.overlay(
    RoundedRectangle(cornerRadius: 8)
        .stroke(Color.kTealMid, lineWidth: 2)
        .opacity(isFocused ? 1 : 0)
)

// VoiceOver labels
Image(systemName: "lock.fill")
    .accessibilityLabel("Privacy — content de-identified")

// Contrast — verified pairs (WCAG AA):
// kTextPrimary (#1E3230) on kBgPrimary (#F2EDE4): ✓ passes
// kTextInverse (#FFFFFF) on kTealPrimary (#2C5F5A): ✓ passes
// kTextPrimary (#D8F0EC) on kBgPrimary (#0D1F1C) dark: ✓ passes
// kSandAccent on kBgPrimary light: check — may need kSandAccent darkened
//   to #A87C44 for body text use. Fine for decorative/data use at current value.
```

---

## 12. macOS Window Configuration

```swift
@main
struct KoreroApp: App {
    var body: some Scene {
        WindowGroup {
            AppShell()
                .preferredColorScheme(nil) // respect system setting
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 620)
    }
}

// NSVisualEffectView for native blur (use when .ultraThinMaterial is insufficient)
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
```

---

## 13. Do Not

```
// NEVER do these:
❌ Flat opaque white or grey cards — everything is glass (.glassPanel())
❌ Color.black or #000000 anywhere in the UI
❌ .font(.system(...)) as primary typeface — always Lora or Source Sans 3
❌ Purple, pink, red outside destructive/error states
❌ .animation on Text content
❌ cornerRadius > 14 on panels (pills: 20 is fine)
❌ More than 4 metrics in MetricsBar
❌ H2 / .kH2 in any colour other than .kTealPrimary
❌ Emoji as icons — use SF Symbols
❌ Glass opacity below 0.05 (invisible on dark substrate)
❌ Gradient backgrounds as substitutes for ambient pools
❌ .bold() modifier — use explicit font weight variants (kBodyMed, kH1 etc.)
```

---

## 14. Quick Reference Card

```
Fonts:       Lora (headings) · Source Sans 3 (UI/body)
H2 colour:   ALWAYS .kTealPrimary
Glass:       .glassPanel() / .glassPanelSm() modifiers
Accent:      .accentStripe(.teal / .sand / .seaGlass)
Bg:          AmbientBackground() — always at root
Spacing:     .spXS(4) .spSM(8) .spMD(12) .spLG(16) .spXL(24)
Icons:       SF Symbols, .light weight, KIconSize enum
Animation:   .kDefault(0.2s) .kPanel(0.25s) .kMetric(0.6s) .kRing(0.8s)
Dark mode:   Asset catalog — Any/Dark variants on all kColor tokens
Motion:      Always check @Environment(\.accessibilityReduceMotion)
```
