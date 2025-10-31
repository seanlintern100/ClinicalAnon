# AI Features Configuration

This document explains how to enable or disable AI features in the Redactor app using conditional compilation.

## Overview

All AI-related features (Ollama integration, AI detection modes, hybrid detection) are wrapped in `#if ENABLE_AI_FEATURES` conditional compilation blocks. This allows you to:

1. **Keep the code in your repository** for future use
2. **Completely exclude it from the build** (reduces binary size, removes all AI functionality)
3. **Easily toggle features** by changing a single build setting

## How to Configure

### Option 1: Disable AI Features (Default for now)

To build the app WITHOUT AI features:

1. Open `Redactor.xcodeproj` in Xcode
2. Select the **Redactor** target
3. Go to **Build Settings** tab
4. Search for "Swift Compiler - Custom Flags"
5. Find **Other Swift Flags** (`OTHER_SWIFT_FLAGS`)
6. Make sure **ENABLE_AI_FEATURES** is NOT defined (remove it if present)

The app will now build with:
- ✅ Pattern-based detection only (offline, fast)
- ❌ No Ollama/LLM integration
- ❌ No AI detection mode
- ❌ No hybrid detection mode
- ❌ No model selector UI

### Option 2: Enable AI Features

To build the app WITH AI features:

1. Open `Redactor.xcodeproj` in Xcode
2. Select the **Redactor** target
3. Go to **Build Settings** tab
4. Search for "Swift Compiler - Custom Flags"
5. Find **Other Swift Flags** (`OTHER_SWIFT_FLAGS`)
6. Add the following for Debug configuration:
   ```
   -D ENABLE_AI_FEATURES
   ```
7. Add the same for Release configuration (if desired)

The app will now build with:
- ✅ Pattern-based detection
- ✅ AI model detection (requires Ollama)
- ✅ Hybrid detection (AI + patterns)
- ✅ Model selector UI
- ✅ Detection mode picker UI

## Command Line Build

### Build WITHOUT AI features:
```bash
xcodebuild -project Redactor.xcodeproj -scheme Redactor -configuration Debug build
```

### Build WITH AI features:
```bash
xcodebuild -project Redactor.xcodeproj -scheme Redactor -configuration Debug build OTHER_SWIFT_FLAGS="-D ENABLE_AI_FEATURES"
```

## What Code Is Affected?

The following files contain conditional compilation blocks:

### Services:
- **AnonymizationEngine.swift**
  - `DetectionMode` enum (removes `.aiModel` and `.hybrid` cases)
  - `detectWithAI()` method
  - `mergeEntities()` method
  - `ollamaService` property
  - Default detection mode (uses `.patterns` when disabled)

### Views:
- **AnonymizationView.swift**
  - `DetectionModePicker` component (hidden)
  - `ModelBadge` component (hidden)
  - Initialization without `ollamaService` parameter

- **ClinicalAnonApp.swift**
  - OllamaService initialization in app entry point

### UI Changes When Disabled:
- Header shows only "Redactor" title (no mode picker, no model badge)
- Only "Pattern Detection (Fast)" is available
- No AI-related settings or controls visible

## Verification

After changing the build flag:

1. **Clean build folder**: Product → Clean Build Folder (⇧⌘K)
2. **Build the project**: Product → Build (⌘B)
3. **Check for errors**: All conditional blocks should compile cleanly
4. **Run the app**: Product → Run (⌘R)
5. **Verify UI**: Check that AI controls are visible/hidden as expected

## Troubleshooting

### Build Errors After Changing Flag

If you get compilation errors:
1. Clean the build folder (⇧⌘K)
2. Quit Xcode
3. Delete `~/Library/Developer/Xcode/DerivedData/Redactor-*`
4. Reopen Xcode and rebuild

### "Cannot find 'OllamaService' in scope"

This means the flag is not set correctly. Either:
- Set `ENABLE_AI_FEATURES` flag in build settings, OR
- Don't reference OllamaService in code that isn't wrapped

### UI Elements Still Showing

Make sure you:
1. Cleaned the build folder
2. The flag is set in **both** Debug and Release configurations (if needed)
3. Selected the correct target (not a test target)

## Restoring AI Features

To restore AI features in the future:

1. Set the `ENABLE_AI_FEATURES` flag in build settings (see Option 2 above)
2. Clean and rebuild
3. All AI code will be included in the build
4. No code changes needed - everything is already in place!

## Notes

- The code remains in the repository even when AI features are disabled
- You can commit code with the flag OFF and other developers can enable it
- Consider using different configurations for App Store vs Development builds
- Binary size will be smaller when AI features are disabled
