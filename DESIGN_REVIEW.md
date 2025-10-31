# Redactor - UI/UX Design Review
**Design Philosophy:** Modern, Simple, macOS Sequoia Native
**Review Date:** 2025-11-01
**Reviewed By:** Claude (Graphic Designer Role)

---

## Executive Summary

The current Redactor UI demonstrates **solid fundamentals** with a clean three-pane layout, consistent spacing, and a well-structured design system. However, to achieve a truly **modern macOS Sequoia aesthetic**, we need to refine several visual elements:

### Current Strengths ✅
- **Excellent information architecture** - Three-pane workflow is logical
- **Consistent design tokens** - Colors, spacing, typography are well-defined
- **Good color palette** - Professional teal, warm neutrals
- **Clean typography hierarchy** - Lora + Source Sans 3 pairing works well

### Areas for Polish 🎨
1. **Corner radius inconsistency** - Mix of sharp and rounded elements
2. **Flat visual hierarchy** - Lacks depth cues for active/inactive states
3. **Button styling** - Too angular for modern macOS aesthetic
4. **Column separation** - No visual breathing room between panes
5. **Lack of elevation** - Everything feels on the same z-plane

---

## Detailed Recommendations

### 1. Corner Radius Modernization ⭐️ HIGH IMPACT

**Current State:**
- Buttons: `8px` (CornerRadius.medium)
- Cards: `8px` (CornerRadius.medium)
- Sidebar items: Mixed/inconsistent

**Recommended Changes:**

```swift
struct CornerRadius {
    // OLD VALUES (commented)
    // static let small: CGFloat = 4
    // static let medium: CGFloat = 8
    // static let large: CGFloat = 12
    // static let xlarge: CGFloat = 16

    // NEW VALUES - More "soft" macOS Sequoia style
    static let small: CGFloat = 6      // Up from 4px
    static let medium: CGFloat = 10    // Up from 8px
    static let large: CGFloat = 14     // Up from 12px
    static let xlarge: CGFloat = 20    // Up from 16px
    static let xxlarge: CGFloat = 24   // NEW - for major UI elements
}
```

**Why This Matters:**
- macOS Sequoia embraces **softer, more rounded corners**
- Creates a more **approachable, friendly** aesthetic
- Aligns with SF Symbols icon style (which have generous rounding)
- Modern apps (Mail, Notes, Safari) all use 10-12px+ corner radius

**Visual Impact:** 🟢🟢🟢🟢🟢 (Very High)

---

### 2. Button Style Refinement ⭐️ HIGH IMPACT

**Current Issues:**
- Buttons feel **flat and boxy**
- No hover states or micro-interactions visible in code
- Corner radius too small for modern look

**Recommended Primary Button Style:**

```swift
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.button)
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.vertical, DesignSystem.Spacing.small + 2) // Slightly more compact
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large) // NEW: 14px instead of 8px
                    .fill(
                        configuration.isPressed
                            ? DesignSystem.Colors.primaryTeal.opacity(0.8)
                            : DesignSystem.Colors.primaryTeal
                    )
                    .shadow(
                        color: DesignSystem.Colors.primaryTeal.opacity(0.3),
                        radius: configuration.isPressed ? 2 : 4,
                        x: 0,
                        y: configuration.isPressed ? 1 : 2
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0) // Subtle press animation
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
```

**Recommended Secondary Button Style:**

```swift
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.caption) // Smaller for secondary actions
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium) // 10px
                    .fill(
                        configuration.isPressed
                            ? DesignSystem.Colors.surface.opacity(0.7)
                            : DesignSystem.Colors.surface
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .strokeBorder(
                                DesignSystem.Colors.border,
                                lineWidth: configuration.isPressed ? 0.5 : 1
                            )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
```

**Key Improvements:**
- ✅ **More generous corner radius** (10-14px vs 8px)
- ✅ **Subtle shadow on primary** - Creates depth
- ✅ **Press animation** - Tactile feedback (scale effect)
- ✅ **Lighter border on press** - Visual feedback

**Visual Impact:** 🟢🟢🟢🟢⚪️ (High)

---

### 3. Column/Pane Visual Hierarchy ⭐️ MEDIUM-HIGH IMPACT

**Current Issue:**
- All three panes (Original, Redacted, Restored) look **visually identical**
- Hard to tell which is the "active" or "primary" column
- No depth cues

**Recommended Solution: Subtle Elevation System**

Add these to DesignSystem.swift:

```swift
struct Elevation {
    /// Recessed - for input/editable areas (slight inset shadow)
    static let recessed = ElevationStyle(
        background: Color.black.opacity(0.02),
        innerShadow: true,
        shadowColor: Color.black.opacity(0.08),
        shadowRadius: 3,
        shadowOffset: (x: 0, y: 1)
    )

    /// Base - for standard surfaces (no shadow)
    static let base = ElevationStyle(
        background: Color.clear,
        innerShadow: false,
        shadowColor: Color.clear,
        shadowRadius: 0,
        shadowOffset: (x: 0, y: 0)
    )

    /// Lifted - for result/output areas (subtle drop shadow)
    static let lifted = ElevationStyle(
        background: Color.white.opacity(0.02),
        innerShadow: false,
        shadowColor: Color.black.opacity(0.06),
        shadowRadius: 8,
        shadowOffset: (x: 0, y: 2)
    )

    struct ElevationStyle {
        let background: Color
        let innerShadow: Bool
        let shadowColor: Color
        let shadowRadius: CGFloat
        let shadowOffset: (x: CGFloat, y: CGFloat)
    }
}
```

**Apply to Columns:**

```swift
// LEFT PANE (Original Text) - Recessed (input area)
.background(
    DesignSystem.Colors.surface
        .overlay(DesignSystem.Elevation.recessed.background)
)
.overlay(
    // Optional: very subtle inner border to emphasize recessed feeling
    RoundedRectangle(cornerRadius: 0)
        .strokeBorder(Color.black.opacity(0.04), lineWidth: 1)
        .padding(1)
)

// MIDDLE PANE (Redacted Text) - Lifted (primary output)
.background(DesignSystem.Colors.surface)
.shadow(
    color: DesignSystem.Elevation.lifted.shadowColor,
    radius: DesignSystem.Elevation.lifted.shadowRadius,
    x: DesignSystem.Elevation.lifted.shadowOffset.x,
    y: DesignSystem.Elevation.lifted.shadowOffset.y
)

// RIGHT PANE (Restored Text) - Base (secondary output)
.background(DesignSystem.Colors.surface)
```

**Why This Works:**
- ✅ **Guides user attention** - Middle pane (Redacted) is the primary output
- ✅ **Subtle depth** - Not overdone, just enough to create hierarchy
- ✅ **Input vs Output distinction** - Recessed input, lifted output
- ✅ **Modern macOS pattern** - Mail app uses similar elevation cues

**Visual Impact:** 🟢🟢🟢🟢⚪️ (High)

---

### 4. Column Spacing & Breathing Room ⭐️ MEDIUM IMPACT

**Current Issue:**
- HSplitView creates **tight, claustrophobic** columns
- Dividers are harsh 1px lines
- No visual padding between content areas

**Recommended Changes:**

```swift
// Add subtle spacing between columns
HSplitView {
    // ... columns
}
.background(DesignSystem.Colors.background) // Shows through as "gap"

// Make Dividers softer
Divider()
    .background(DesignSystem.Colors.border.opacity(0.5)) // Lighter, less harsh
```

**Add Inner Padding to Panes:**

```swift
// Each pane should have rounded inner corners
.background(
    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
        .fill(DesignSystem.Colors.surface)
        .padding(2) // Creates tiny gap from divider
)
```

**Visual Impact:** 🟢🟢🟢⚪️⚪️ (Medium)

---

### 5. Sidebar Polish ⭐️ MEDIUM IMPACT

**Current Issues:**
- Entity rows feel cramped
- Collapsed state is too minimal
- No hover states

**Recommended Improvements:**

```swift
struct EntitySidebarRow: View {
    let entity: Entity
    let isActive: Bool
    let onToggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // ... content
        }
        .padding(.vertical, 8) // More breathing room
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small) // 6px
                .fill(
                    isHovered
                        ? DesignSystem.Colors.primaryTeal.opacity(0.08)
                        : (isActive ? Color.clear : DesignSystem.Colors.surface.opacity(0.5))
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
```

**Visual Impact:** 🟢🟢🟢⚪️⚪️ (Medium)

---

### 6. Micro-interactions & Animations ⭐️ LOW-MEDIUM IMPACT

**Add subtle animations throughout:**

```swift
// Copy button with spring animation
.scaleEffect(viewModel.justCopiedAnonymized ? 1.05 : 1.0)
.animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.justCopiedAnonymized)

// Entity highlight fade-in
.opacity(entity.isNew ? 0 : 1)
.animation(.easeIn(duration: 0.4), value: entity.isNew)

// Sidebar expand/collapse
.animation(.spring(response: 0.35, dampingFraction: 0.75), value: isCollapsed)
```

**Visual Impact:** 🟢🟢⚪️⚪️⚪️ (Low-Medium)

---

### 7. Color Refinements ⭐️ LOW IMPACT

**Current Colors Are Good**, but consider:

```swift
// Slightly warmer background for less clinical feel
static let warmWhite = Color(red: 252/255, green: 249/255, blue: 246/255) // Warmer
// Was: Color(red: 250/255, green: 247/255, blue: 244/255)

// Slightly deeper teal for better contrast
static let primaryTeal = Color(red: 8/255, green: 97/255, blue: 114/255) // Deeper
// Was: Color(red: 10/255, green: 107/255, blue: 124/255)
```

**Visual Impact:** 🟢⚪️⚪️⚪️⚪️ (Low)

---

## Implementation Priority

### Phase 1 - Quick Wins (30 mins)
1. ✅ Update corner radius values in DesignSystem
2. ✅ Apply new corner radius to buttons
3. ✅ Add button press animations

### Phase 2 - Core Polish (1-2 hours)
4. ✅ Implement elevation system
5. ✅ Apply elevation to three columns
6. ✅ Refine button styles with shadows

### Phase 3 - Fine Tuning (1 hour)
7. ✅ Add hover states to sidebar rows
8. ✅ Soften dividers
9. ✅ Add micro-interactions

### Phase 4 - Optional Refinements (30 mins)
10. ⚪️ Adjust background warmth
11. ⚪️ Fine-tune teal color depth

---

## Visual Mockup (Text Description)

**Before:**
```
┌─────────────────────────────────────────────┐
│ Header (flat, sharp corners)                │
├─────────────────────────────────────────────┤
│ [Col 1]  │  [Col 2]  │  [Col 3]             │
│ Sharp    │  Sharp    │  Sharp                │
│ borders  │  borders  │  borders              │
│ Same     │  Same     │  Same                 │
│ depth    │  depth    │  depth                │
└─────────────────────────────────────────────┘
```

**After:**
```
╭─────────────────────────────────────────────╮
│ Header (soft, rounded)                      │
├─────────────────────────────────────────────┤
│ ╭─Col 1─╮ │ ╭─Col 2─╮ │ ╭─Col 3─╮         │
│ │Recessed│ │ │Lifted │ │ │ Base  │         │
│ │(input) │ │ │OUTPUT │ │ │       │         │
│ │        │ │ │ ▲▲▲   │ │ │       │         │
│ ╰────────╯ │ ╰───────╯ │ ╰───────╯         │
└─────────────────────────────────────────────┘
         Soft shadows create depth hierarchy
```

---

## Design Rationale

### Why Rounded Corners?
- **Industry standard** - Every modern macOS app uses generous rounding
- **Psychological warmth** - Sharp corners feel "cold" and technical
- **SF Symbols alignment** - Apple's icon system is highly rounded
- **Accessibility** - Softer edges are easier on the eyes during long sessions

### Why Elevation/Depth?
- **Visual hierarchy** - Guides user's eye to primary action/output
- **Spatial organization** - Helps brain categorize "input" vs "output" areas
- **Reduced cognitive load** - Subtle depth cues eliminate need to read labels
- **Modern aesthetic** - Flat design 2.0 embraces subtle shadows

### Why Micro-interactions?
- **Feedback** - Confirms user actions (press, hover, copy)
- **Delight** - Small animations make software feel "alive"
- **Professionalism** - Polished apps have thoughtful interactions
- **Reduced errors** - Visual feedback prevents accidental clicks

---

## Technical Notes

### Performance Considerations
- All shadows use low opacity (`0.06-0.1`) → minimal GPU impact
- Animations are hardware-accelerated (transform/opacity only)
- Corner radius rendering is optimized in SwiftUI
- No bitmap effects or blurs → stays performant

### Dark Mode Compatibility
- All recommendations work in dark mode
- Shadows become slightly lighter in dark mode
- Corner radius is theme-independent
- Test both modes after implementation

---

## Conclusion

The Redactor UI has **excellent bones**. These refinements will transform it from "clean and functional" to **"beautifully modern and professional"**.

The key is **subtlety** - we're not adding flashy effects, just refined details that compound into a polished whole.

**Estimated Total Implementation Time:** 3-4 hours
**Expected Visual Impact:** ⭐️⭐️⭐️⭐️⚪️ (Very High)

---

## Questions for Product Owner

1. **Brand identity** - Is the current teal color sacred, or can we deepen it slightly?
2. **Animation appetite** - How much motion is acceptable? (Some users prefer reduced motion)
3. **Target audience** - Are users primarily clinicians (prefer subtle) or general users?
4. **Platform scope** - macOS only, or also iOS/iPad in future? (Affects design decisions)

---

*End of Design Review*
