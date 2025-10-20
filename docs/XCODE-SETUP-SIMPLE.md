# Simplified Xcode Setup Guide
## Quick Start for ClinicalAnon

✅ **Fonts are already downloaded and ready!**

All 6 font files (Lora + Source Sans 3) are in `ClinicalAnon/Resources/Fonts/`

---

## Option 1: Quick Setup (Recommended - 5 minutes)

### Step 1: Open Xcode
Launch Xcode 15 or later

### Step 2: Create New Project
1. File → New → Project
2. Select **macOS** → **App**
3. Click **Next**

### Step 3: Configure Project
- **Product Name:** `ClinicalAnon`
- **Team:** Your team or "None"
- **Organization Name:** `3 Big Things`
- **Organization Identifier:** `com.3bigthings` (or your choice)
- **Interface:** SwiftUI
- **Language:** Swift
- **Storage:** None
- **Include Tests:** ✅

Click **Next**

### Step 4: Choose Save Location
**IMPORTANT:**
- Navigate to: `/Users/seanversteegh/Redactor/`
- When prompted that "ClinicalAnon" already exists, choose **"Merge"** or **"Replace"**
- Xcode will create the project and merge with existing files

### Step 5: Add Existing Files to Project

In Xcode Project Navigator:

1. **Delete** the template `ContentView.swift` (we have our own)
2. **Delete** the template `ClinicalAnonApp.swift` (we have our own)

3. Right-click on `ClinicalAnon` (main group) →  **"Add Files to ClinicalAnon"**
4. Select our `ClinicalAnonApp.swift`
5. ✅ **Add to targets:** ClinicalAnon
6. Click **Add**

7. Create groups (right-click `ClinicalAnon` → **New Group**):
   - `Utilities`
   - `Views`
   - `ViewModels`
   - `Models`
   - `Services`
   - `Resources`

8. **Add Utilities:**
   - Right-click `Utilities` group → **"Add Files..."**
   - Navigate to `ClinicalAnon/Utilities/`
   - Select `DesignSystem.swift` and `AppError.swift`
   - ✅ **Add to targets**
   - Click **Add**

9. **Add Fonts:**
   - Right-click `Resources` → **New Group** → name it `Fonts`
   - Right-click `Fonts` group → **"Add Files..."**
   - Navigate to `ClinicalAnon/Resources/Fonts/`
   - Select all 6 TTF files
   - ✅ **Copy items if needed**
   - ✅ **Add to targets**
   - Click **Add**

### Step 6: Fix macOS Color API

Open `Utilities/DesignSystem.swift`

Find line ~108 (the `Color` extension):

Replace this:
```swift
extension Color {
    init(light: Color, dark: Color) {
        self.init(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
    }
}
```

With this (macOS compatible):
```swift
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
```

### Step 7: Configure Info.plist for Fonts

1. Select project (blue icon) in Navigator
2. Select **ClinicalAnon** target
3. **Info** tab
4. Find or add key: **Fonts provided by application**
5. Add 6 items:
   ```
   Fonts/Lora-Regular.ttf
   Fonts/Lora-Bold.ttf
   Fonts/Lora-Italic.ttf
   Fonts/SourceSans3-Regular.ttf
   Fonts/SourceSans3-SemiBold.ttf
   Fonts/SourceSans3-Bold.ttf
   ```

### Step 8: Build & Run

1. Select **My Mac** as run destination
2. Press **Cmd+B** to build
3. Press **Cmd+R** to run

✅ **You should see the ClinicalAnon window with custom fonts!**

---

## Option 2: Use Provided Script (If Automation Works)

We've created a `create-xcode-project.sh` script that attempts to automate the setup.

```bash
cd /Users/seanversteegh/Redactor
./create-xcode-project.sh
```

Then open `ClinicalAnon.xcodeproj` in Xcode.

---

## Troubleshooting

### Fonts Don't Load
1. Check `Info.plist` has all 6 font files listed
2. Product → Clean Build Folder (Cmd+Shift+K)
3. Verify fonts are in "Copy Bundle Resources":
   - Project → Target → Build Phases → Copy Bundle Resources
   - All 6 TTF files should be there

### Build Errors
- **"No such module SwiftUI"**: Check deployment target is macOS 13.0+
- **"Cannot find NSColor"**: Apply the fix from Step 6
- **Missing files**: Ensure all files added to target

### Window Doesn't Appear
- Check `ClinicalAnonApp.swift` has `.defaultSize(width: 1200, height: 700)`
- Try changing `.windowStyle(.hiddenTitleBar)` to `.windowStyle(.automatic)`

---

## Verification Checklist

- [ ] Project builds without errors
- [ ] App runs and window appears
- [ ] Title shows in Lora font (serif)
- [ ] Body text shows in Source Sans 3 (sans-serif)
- [ ] Card component displays with shadow
- [ ] Phase 1 checklist visible
- [ ] Colors match design system

---

## Next Steps

Once Phase 1 is verified:
- Commit changes to git
- Update Phase-Documents-Checklist.md
- Begin Phase 2: Setup Flow & Ollama Integration

---

*If you encounter issues, refer to the comprehensive docs/PHASE-1-SETUP-GUIDE.md*
