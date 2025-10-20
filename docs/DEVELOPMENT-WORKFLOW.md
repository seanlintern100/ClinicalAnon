# Development Workflow with xcodegen
## How to Make Changes and Update the Xcode Project

This project uses **xcodegen** to automatically generate the Xcode project from a YAML configuration file. This means you never edit the `.xcodeproj` file manually.

---

## Quick Reference

```bash
# Add a new Swift file → Regenerate project
xcodegen generate

# Build to check for errors
xcodebuild -project Redactor.xcodeproj -scheme Redactor build

# Open in Xcode to run
open Redactor.xcodeproj
```

---

## Complete Development Workflow

### Scenario 1: Adding a New Swift File

**Example:** You want to add `SetupManager.swift` to the `Utilities/` folder.

#### Step 1: Create the file
```bash
# Create the file in the appropriate directory
touch ClinicalAnon/Utilities/SetupManager.swift

# Or use your editor
code ClinicalAnon/Utilities/SetupManager.swift
```

#### Step 2: Write your code
Edit the file with your Swift code.

#### Step 3: Regenerate the Xcode project
```bash
xcodegen generate
```

**What this does:**
- Scans the `ClinicalAnon/` directory for all Swift files
- Automatically adds new files to the Xcode project
- Updates `Redactor.xcodeproj/project.pbxproj`
- Preserves all your build settings

#### Step 4: Verify it builds
```bash
xcodebuild -project Redactor.xcodeproj -scheme Redactor build
```

#### Step 5: Open in Xcode and test
```bash
open Redactor.xcodeproj
# Press Cmd+R to run
```

#### Step 6: Commit your changes
```bash
git add ClinicalAnon/Utilities/SetupManager.swift
git add Redactor.xcodeproj/  # The regenerated project
git commit -m "Add SetupManager for Ollama detection"
git push
```

---

### Scenario 2: Adding Multiple Files at Once

**Example:** Adding Phase 2 files (SetupManager, SetupView, OllamaService)

#### Step 1: Create all files
```bash
touch ClinicalAnon/Utilities/SetupManager.swift
touch ClinicalAnon/Views/SetupView.swift
touch ClinicalAnon/Services/OllamaService.swift
```

#### Step 2: Write code in all files
Edit each file with your implementation.

#### Step 3: Regenerate once
```bash
xcodegen generate
```

All three files are now in the Xcode project!

#### Step 4: Build and verify
```bash
xcodebuild -project Redactor.xcodeproj -scheme Redactor build
```

---

### Scenario 3: Modifying Existing Files

**Example:** Updating `DesignSystem.swift`

#### Step 1: Edit the file
```bash
# Open in your editor
code ClinicalAnon/Utilities/DesignSystem.swift

# Or open directly in Xcode
open -a Xcode ClinicalAnon/Utilities/DesignSystem.swift
```

#### Step 2: Make your changes
Edit the Swift code as needed.

#### Step 3: No need to regenerate!
**Modifying existing files doesn't require regeneration.**

The file is already in the project, so just:

```bash
# Build to check for errors
xcodebuild -project Redactor.xcodeproj -scheme Redactor build

# Or build in Xcode (Cmd+B)
```

#### Step 4: Commit
```bash
git add ClinicalAnon/Utilities/DesignSystem.swift
git commit -m "Update DesignSystem with new colors"
```

---

### Scenario 4: Changing Build Settings

**Example:** Changing deployment target or adding a compiler flag

#### Step 1: Edit project.yml
```bash
code project.yml
```

#### Step 2: Modify settings
```yaml
targets:
  Redactor:
    settings:
      base:
        MACOSX_DEPLOYMENT_TARGET: "14.0"  # Changed from 13.0
        SWIFT_VERSION: "5.10"             # Updated
        # Add other settings here
```

#### Step 3: Regenerate
```bash
xcodegen generate
```

#### Step 4: Verify
```bash
xcodebuild -project Redactor.xcodeproj -scheme Redactor -showBuildSettings | grep DEPLOYMENT
```

---

### Scenario 5: Adding a New Resource (Asset, Font, etc.)

**Example:** Adding a new font file

#### Step 1: Add the resource
```bash
cp ~/Downloads/NewFont.ttf ClinicalAnon/Resources/Fonts/
```

#### Step 2: Update Info.plist (if needed)
```bash
code ClinicalAnon/Resources/Info.plist
```

Add to the `UIAppFonts` array:
```xml
<key>UIAppFonts</key>
<array>
    <string>Fonts/NewFont.ttf</string>
    <!-- ... other fonts ... -->
</array>
```

#### Step 3: Update project.yml (if adding new resource folder)
```yaml
resources:
  - path: ClinicalAnon/Resources/Fonts
  - path: ClinicalAnon/Resources/NewFolder  # Add this
```

#### Step 4: Regenerate
```bash
xcodegen generate
```

---

### Scenario 6: Deleting a File

**Example:** Removing an obsolete Swift file

#### Step 1: Delete the file
```bash
rm ClinicalAnon/Services/OldService.swift
```

#### Step 2: Regenerate
```bash
xcodegen generate
```

The file is automatically removed from the Xcode project!

#### Step 3: Commit
```bash
git add -A  # Captures deletions
git commit -m "Remove obsolete OldService"
```

---

### Scenario 7: Creating a New Folder/Group

**Example:** Adding a `Models/` subfolder for entity models

#### Step 1: Create the directory
```bash
mkdir -p ClinicalAnon/Models/Entities
```

#### Step 2: Add files to it
```bash
touch ClinicalAnon/Models/Entities/User.swift
touch ClinicalAnon/Models/Entities/Session.swift
```

#### Step 3: Regenerate
```bash
xcodegen generate
```

The new folder structure appears in Xcode automatically!

**Note:** xcodegen mirrors your file system structure in Xcode groups.

---

## When to Regenerate vs. When Not To

### ✅ Regenerate When:
- Adding new Swift files
- Deleting Swift files
- Renaming Swift files
- Adding new resources (fonts, assets)
- Changing build settings in project.yml
- Modifying project structure
- Adding/removing targets
- After pulling changes from git

### ❌ Don't Need to Regenerate When:
- Editing existing Swift files
- Changing code within files
- Building or running the app
- Debugging
- Using Xcode normally

---

## Troubleshooting

### "File not found in Xcode"
**Problem:** Added a file but Xcode doesn't see it.

**Solution:**
```bash
xcodegen generate
# Then restart Xcode
```

### "Build fails after adding file"
**Problem:** New file has compile errors.

**Solution:**
Check the file syntax. The regeneration worked, but your code has issues.

```bash
# See the actual error
xcodebuild -project Redactor.xcodeproj -scheme Redactor build 2>&1 | grep error
```

### "Project file merge conflict"
**Problem:** Git conflict in `project.pbxproj` after pulling.

**Solution:**
```bash
# Discard the conflict, regenerate from scratch
git checkout --theirs Redactor.xcodeproj/project.pbxproj
xcodegen generate

# Or just regenerate
xcodegen generate
```

### "Xcode doesn't show my changes"
**Problem:** Made changes but Xcode seems out of date.

**Solution:**
```bash
# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/Redactor-*

# Regenerate
xcodegen generate

# Restart Xcode
```

---

## Best Practices

### 1. Regenerate After Pulling from Git
```bash
git pull origin main
xcodegen generate
```

Always regenerate after pulling to ensure your Xcode project matches the current file structure.

### 2. Check Build Before Committing
```bash
xcodebuild -project Redactor.xcodeproj -scheme Redactor build
```

Make sure the project builds before committing.

### 3. Commit Both Source and Project
```bash
git add ClinicalAnon/NewFile.swift
git add Redactor.xcodeproj/
git commit -m "Add NewFile feature"
```

Always commit both the source files AND the regenerated project.

### 4. Use Meaningful Commit Messages
```bash
# Good
git commit -m "Add SetupManager for Ollama detection and installation"

# Bad
git commit -m "updates"
```

### 5. Keep project.yml in Sync
If you add a new build setting manually in Xcode, it will be lost on next regenerate. Always update project.yml instead.

---

## Development Loop

The typical development loop looks like this:

```bash
# 1. Start with latest code
git pull origin main
xcodegen generate

# 2. Make changes (add/edit files)
code ClinicalAnon/Services/NewService.swift

# 3. If you added new files, regenerate
xcodegen generate

# 4. Build to check
xcodebuild -project Redactor.xcodeproj -scheme Redactor build

# 5. Run and test in Xcode
open Redactor.xcodeproj
# Press Cmd+R

# 6. Commit when ready
git add .
git commit -m "Implement NewService for feature X"
git push origin main
```

---

## IDE Integration

### VS Code
If you're using VS Code for Swift development:

```bash
# Edit files in VS Code
code ClinicalAnon/

# Build via CLI
xcodebuild -project Redactor.xcodeproj -scheme Redactor build

# Open in Xcode only when you need to run/debug
open Redactor.xcodeproj
```

### Xcode Only
If you prefer Xcode for everything:

1. Open `Redactor.xcodeproj`
2. Add files via: File → New → File...
3. Place them in the correct folder in Finder
4. Run `xcodegen generate` in Terminal
5. Xcode will prompt to reload - click "Reload"

---

## Summary

**Key Principle:**
- **File system is source of truth** (not the .xcodeproj)
- **xcodegen reads file system** → generates Xcode project
- **Never edit .xcodeproj manually** → always regenerate

**Simple Rules:**
1. Add/remove files on file system
2. Run `xcodegen generate`
3. Build and test
4. Commit both code and project

**Result:**
- No merge conflicts in .xcodeproj
- Project structure always matches file system
- Team stays in sync
- CI/CD can regenerate project easily

---

## Quick Command Reference

```bash
# Regenerate project
xcodegen generate

# Build
xcodebuild -project Redactor.xcodeproj -scheme Redactor build

# Clean build
rm -rf ~/Library/Developer/Xcode/DerivedData/Redactor-*
xcodebuild -project Redactor.xcodeproj -scheme Redactor clean build

# Open in Xcode
open Redactor.xcodeproj

# List schemes
xcodebuild -project Redactor.xcodeproj -list

# Show build settings
xcodebuild -project Redactor.xcodeproj -scheme Redactor -showBuildSettings
```

---

**Questions?** Check `.claude.md` for more CLI commands and project context.
