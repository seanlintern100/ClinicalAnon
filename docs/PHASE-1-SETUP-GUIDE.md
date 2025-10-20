# Phase 1 Setup Guide
## Creating the Xcode Project and Integrating Fonts

**Status:** Ready for manual setup
**Estimated Time:** 30 minutes

---

## Overview

Phase 1 Swift files have been created. Now you need to:
1. Create the Xcode project
2. Download and integrate custom fonts
3. Add Swift files to the project
4. Verify everything builds

---

## Step 1: Create Xcode Project

### 1.1 Open Xcode
- Launch Xcode 15 or later
- Click "Create New Project" (or File → New → Project)

### 1.2 Project Template
- Choose **macOS** tab
- Select **App** template
- Click **Next**

### 1.3 Project Configuration
Fill in the following:
- **Product Name:** `ClinicalAnon`
- **Team:** Select your Apple Developer account (or leave as "None" for now)
- **Organization Name:** `3 Big Things`
- **Organization Identifier:** `com.3bigthings` (or your preference)
- **Bundle Identifier:** Will auto-populate as `com.3bigthings.ClinicalAnon`
- **Interface:** `SwiftUI`
- **Language:** `Swift`
- **Storage:** `None` (we're using in-memory only)
- **Include Tests:** ✅ **Checked**

Click **Next**

### 1.4 Save Location
- Navigate to: `/Users/seanversteegh/Redactor/`
- **Important:** When saving, Xcode will create a `ClinicalAnon` folder
- Since we already have a `ClinicalAnon` folder with our Swift files:
  - Either rename the existing folder temporarily (e.g., `ClinicalAnon_Files`)
  - Or create the project first, then merge our files in

**Recommended approach:**
```bash
# In Terminal, from /Users/seanversteegh/Redactor/
mv ClinicalAnon ClinicalAnon_Source
# Then create the Xcode project normally
# After creation, we'll merge the files
```

---

## Step 2: Download Custom Fonts

### 2.1 Download Lora (Serif - for Headings)

**Source:** Google Fonts - https://fonts.google.com/specimen/Lora

1. Visit https://fonts.google.com/specimen/Lora
2. Click "Download family" button (top right)
3. Extract the ZIP file
4. Locate these font files in the `static/` folder:
   - `Lora-Regular.ttf`
   - `Lora-Bold.ttf`
   - `Lora-Italic.ttf`

### 2.2 Download Source Sans 3 (Sans-Serif - for Body)

**Source:** Google Fonts - https://fonts.google.com/specimen/Source+Sans+3

1. Visit https://fonts.google.com/specimen/Source+Sans+3
2. Click "Download family" button
3. Extract the ZIP file
4. Locate these font files in the `static/` folder:
   - `SourceSans3-Regular.ttf`
   - `SourceSans3-SemiBold.ttf`
   - `SourceSans3-Bold.ttf`

### 2.3 Organize Fonts

Create a fonts folder and move the 6 font files:

```bash
# From your Downloads folder (or wherever fonts extracted)
mkdir -p ~/Desktop/ClinicalAnon_Fonts
cp Lora/static/Lora-Regular.ttf ~/Desktop/ClinicalAnon_Fonts/
cp Lora/static/Lora-Bold.ttf ~/Desktop/ClinicalAnon_Fonts/
cp Lora/static/Lora-Italic.ttf ~/Desktop/ClinicalAnon_Fonts/
cp SourceSans3/static/SourceSans3-Regular.ttf ~/Desktop/ClinicalAnon_Fonts/
cp SourceSans3/static/SourceSans3-SemiBold.ttf ~/Desktop/ClinicalAnon_Fonts/
cp SourceSans3/static/SourceSans3-Bold.ttf ~/Desktop/ClinicalAnon_Fonts/
```

You should have 6 TTF files ready to add to the project.

---

## Step 3: Set Up Xcode Project Structure

### 3.1 Add Folder Groups

In Xcode's Project Navigator:

1. Right-click on `ClinicalAnon` folder (yellow icon)
2. Select **New Group**
3. Create these groups (folders):
   - `Views`
   - `Views/Components` (nested under Views)
   - `ViewModels`
   - `Models`
   - `Services`
   - `Utilities`
   - `Resources`
   - `Resources/Fonts` (nested under Resources)

Your structure should look like:
```
ClinicalAnon
├── ClinicalAnonApp.swift (already exists from template)
├── ContentView.swift (delete this - we have our own)
├── Views/
│   └── Components/
├── ViewModels/
├── Models/
├── Services/
├── Utilities/
├── Resources/
│   └── Fonts/
├── Assets.xcassets (already exists)
└── Tests/
```

### 3.2 Delete Template Files

- Delete the default `ContentView.swift` created by Xcode
- We'll replace it with our own

---

## Step 4: Add Font Files to Xcode

### 4.1 Add to Project

1. Select `Resources/Fonts` group in Project Navigator
2. Right-click → **Add Files to "ClinicalAnon"...**
3. Navigate to `~/Desktop/ClinicalAnon_Fonts/`
4. Select all 6 TTF files
5. **Important:** Ensure these options are checked:
   - ✅ **Copy items if needed**
   - ✅ **Create groups** (not folder references)
   - ✅ **Add to targets: ClinicalAnon** (main app target)
6. Click **Add**

### 4.2 Verify Fonts Added

In Project Navigator, under `Resources/Fonts/`, you should see:
- Lora-Regular.ttf
- Lora-Bold.ttf
- Lora-Italic.ttf
- SourceSans3-Regular.ttf
- SourceSans3-SemiBold.ttf
- SourceSans3-Bold.ttf

### 4.3 Update Info.plist

1. In Project Navigator, select `Info.plist` (or the project settings)
2. Click the **Info** tab
3. Add a new key: **Fonts provided by application** (`UIAppFonts`)
4. Add these 6 items as Array entries:
   ```
   Fonts/Lora-Regular.ttf
   Fonts/Lora-Bold.ttf
   Fonts/Lora-Italic.ttf
   Fonts/SourceSans3-Regular.ttf
   Fonts/SourceSans3-SemiBold.ttf
   Fonts/SourceSans3-Bold.ttf
   ```

**Alternative:** Replace the entire Info.plist with our pre-configured one from `ClinicalAnon_Source/Resources/Info.plist`

---

## Step 5: Add Swift Source Files

### 5.1 Add Files to Appropriate Groups

From the `ClinicalAnon_Source` folder we created earlier, add files to their respective groups:

**Utilities:**
1. Right-click `Utilities` group → **Add Files to "ClinicalAnon"...**
2. Navigate to `ClinicalAnon_Source/Utilities/`
3. Select:
   - `DesignSystem.swift`
   - `AppError.swift`
4. ✅ **Copy items if needed**
5. ✅ **Add to targets: ClinicalAnon**
6. Click **Add**

**Main App:**
1. Select the main `ClinicalAnon` group (top level)
2. **Add Files to "ClinicalAnon"...**
3. Select: `ClinicalAnon_Source/ClinicalAnonApp.swift`
4. ✅ **Copy items if needed**
5. Click **Add**
6. **Delete** the template `ClinicalAnonApp.swift` if it asks to replace

### 5.2 Verify File Structure

Your Project Navigator should now show:
```
ClinicalAnon
├── ClinicalAnonApp.swift ✅
├── Views/
│   └── Components/
├── ViewModels/
├── Models/
├── Services/
├── Utilities/
│   ├── DesignSystem.swift ✅
│   └── AppError.swift ✅
├── Resources/
│   ├── Fonts/
│   │   ├── Lora-Regular.ttf ✅
│   │   ├── Lora-Bold.ttf ✅
│   │   ├── Lora-Italic.ttf ✅
│   │   ├── SourceSans3-Regular.ttf ✅
│   │   ├── SourceSans3-SemiBold.ttf ✅
│   │   └── SourceSans3-Bold.ttf ✅
│   └── Info.plist
├── Assets.xcassets
└── Tests/
```

---

## Step 6: Build and Test

### 6.1 Fix UIColor Reference (macOS Issue)

The `DesignSystem.swift` file uses `UIColor`, which is iOS. For macOS, we need `NSColor`.

**Fix in DesignSystem.swift:**

Find this section (around line 108):
```swift
extension Color {
    init(light: Color, dark: Color) {
        self.init(UIColor { traitCollection in
```

Replace with:
```swift
extension Color {
    init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(NSColor(name: nil) { appearance in
            switch appearance.name {
            case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
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

### 6.2 Build the Project

1. Select the **ClinicalAnon** scheme (top left, next to play button)
2. Select **My Mac** as the run destination
3. Press **Cmd+B** to build

**Expected Result:** Build should succeed with 0 errors

### 6.3 Run the App

1. Press **Cmd+R** to run
2. You should see a window with:
   - "ClinicalAnon" title in Lora font (serif)
   - "Privacy-first clinical text anonymization" heading
   - Phase 1 progress checklist
   - A card showing completed items

### 6.4 Verify Fonts Loaded

If fonts don't load (text appears in system font):

**Debug Check:**
Add this temporary code to `ClinicalAnonApp.swift` in the `init()`:

```swift
init() {
    // Debug: Print available fonts
    print("Available font families:")
    for family in NSFontManager.shared.availableFontFamilies {
        print("- \(family)")
        let fonts = NSFontManager.shared.availableMembers(ofFontFamily: family)
        fonts?.forEach { print("  - \($0)") }
    }
}
```

Look for "Lora" and "Source Sans 3" in the console output.

---

## Step 7: Configure Project Settings

### 7.1 General Settings

1. Select the **ClinicalAnon** project (blue icon) in Navigator
2. Select **ClinicalAnon** target
3. **General** tab:
   - **Display Name:** ClinicalAnon
   - **Bundle Identifier:** com.3bigthings.ClinicalAnon (or your choice)
   - **Version:** 1.0
   - **Build:** 1
   - **Deployment Target:** macOS 13.0
   - **Supported Destinations:** ✅ Mac

### 7.2 Signing & Capabilities

1. **Signing & Capabilities** tab:
   - **Automatically manage signing:** ✅ (for development)
   - **Team:** Select your team (or None for local testing)

### 7.3 Build Settings

1. **Build Settings** tab
2. Search for "Swift Language Version"
3. Ensure it's set to **Swift 5** or later

---

## Step 8: Commit to Git

Once everything builds successfully:

```bash
cd /Users/seanversteegh/Redactor/

# Remove the source folder (files now in Xcode project)
rm -rf ClinicalAnon_Source

# Add Xcode project to git
git add .

# Commit
git commit -m "Phase 1 complete: Xcode project setup with design system

- Created macOS SwiftUI project (Xcode 15, macOS 13+)
- Integrated Lora and Source Sans 3 custom fonts
- Implemented complete DesignSystem.swift (colors, typography, spacing)
- Created AppError.swift with comprehensive error handling
- Basic app structure with temporary ContentView for verification

Phase 1 deliverables complete. Ready for Phase 2.

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>"

# Push to GitHub
git push origin main
```

---

## Verification Checklist

Before proceeding to Phase 2, ensure:

- [ ] Xcode project created and opens without errors
- [ ] All 6 font files added to Resources/Fonts/
- [ ] Info.plist lists all fonts in UIAppFonts array
- [ ] DesignSystem.swift compiles without errors
- [ ] AppError.swift compiles without errors
- [ ] ClinicalAnonApp.swift compiles without errors
- [ ] Project builds successfully (Cmd+B)
- [ ] App runs and displays window (Cmd+R)
- [ ] Custom fonts render correctly (Lora for title, Source Sans for body)
- [ ] Card component shows with design system styling
- [ ] Phase 1 progress card displays all items
- [ ] Changes committed to git and pushed to GitHub

---

## Troubleshooting

### Fonts Not Loading

**Problem:** Text appears in system font instead of Lora/Source Sans

**Solutions:**
1. Check Info.plist has UIAppFonts array with all 6 files
2. Verify font files are in the "Copy Bundle Resources" build phase:
   - Select project → Target → Build Phases
   - Expand "Copy Bundle Resources"
   - Ensure all 6 TTF files are listed
3. Check font file names exactly match in code (case-sensitive)
4. Clean build folder: Product → Clean Build Folder (Cmd+Shift+K)
5. Restart Xcode

### Build Errors

**Problem:** "No such module 'SwiftUI'"
- Check Deployment Target is macOS 13.0+
- Ensure Swift version is 5.9+

**Problem:** "Cannot find NSColor in scope"
- Ensure the Color extension fix from Step 6.1 is applied

### Window Doesn't Appear

**Problem:** App runs but no window shows
- Check WindowGroup configuration in ClinicalAnonApp.swift
- Ensure .defaultSize is set
- Try adding .windowStyle(.automatic)

---

## Next Steps

Once Phase 1 verification checklist is complete:

**Ready for Phase 2:** Setup Flow & Ollama Integration
- Implement SetupManager.swift
- Create SetupView.swift
- Implement OllamaService.swift
- Add conditional view rendering

---

## Support

If you encounter issues:
1. Check the troubleshooting section
2. Review console output for errors
3. Verify all steps were followed in order
4. Clean and rebuild

---

*This guide gets Phase 1 ready for development. Follow carefully to ensure a solid foundation.*
