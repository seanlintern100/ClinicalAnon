# Claude Development Notes

## AI Features Removal (2025-11-01)

The AI features (Ollama integration, LLM-based detection) have been made **optional** using conditional compilation. This allows the code to remain in the repository while being completely excluded from builds.

### What Was Done

All AI-related code has been wrapped in `#if ENABLE_AI_FEATURES` conditional compilation blocks:

**Services Modified:**
- `AnonymizationEngine.swift`
  - `DetectionMode` enum - `.aiModel` and `.hybrid` cases
  - `detectWithAI()` and `mergeEntities()` methods
  - `ollamaService` property
  - Default mode set to `.patterns` when AI disabled

**Views Modified:**
- `AnonymizationView.swift`
  - `DetectionModePicker` component (hidden when AI disabled)
  - `ModelBadge` component (hidden when AI disabled)
  - Separate initializers for AI-enabled vs AI-disabled builds

- `ClinicalAnonApp.swift`
  - `OllamaService` initialization

### Current Build Status

**Default Behavior (AI Disabled):**
- ✅ Build succeeds without `ENABLE_AI_FEATURES` flag
- ✅ Pattern-based detection only
- ✅ No AI UI elements visible
- ✅ No Ollama/LLM integration
- ✅ Smaller binary size
- ✅ Fully functional offline detection

**With AI Enabled:**
- ✅ Build succeeds with `-D ENABLE_AI_FEATURES` flag
- ✅ All three detection modes available (AI, Patterns, Hybrid)
- ✅ Full Ollama integration
- ✅ Model selector UI visible
- ✅ Detection mode picker visible

### How to Use

See [AI_FEATURES_SETUP.md](./AI_FEATURES_SETUP.md) for detailed instructions on:
- How to enable/disable AI features
- Build configuration steps
- Command-line build options
- Troubleshooting

### Why Conditional Compilation?

1. **Code Preservation** - All AI code remains in the repository
2. **Build Size** - Excluded code doesn't bloat the binary
3. **No Runtime Overhead** - Completely removed from compiled app
4. **Easy Restoration** - Just flip the build flag
5. **Clean Separation** - No feature flags or if-statements at runtime

### Affected Files

```
ClinicalAnon/
├── Services/
│   └── AnonymizationEngine.swift ✏️ Modified
└── Views/
    └── AnonymizationView.swift ✏️ Modified

ClinicalAnonApp.swift ✏️ Modified
AI_FEATURES_SETUP.md ✨ New
```

### Testing

The build was tested on 2025-11-01 with both configurations:

**Without AI Flag:**
```bash
xcodebuild -project Redactor.xcodeproj -scheme Redactor -configuration Debug build
# Result: ✅ BUILD SUCCEEDED
```

**With AI Flag:**
```bash
xcodebuild -project Redactor.xcodeproj -scheme Redactor -configuration Debug build OTHER_SWIFT_FLAGS="-D ENABLE_AI_FEATURES"
# Result: ✅ BUILD SUCCEEDED
```

---

## Future Development Notes

### Adding New AI Features

When adding new AI-related code in the future, wrap it in conditional compilation:

```swift
#if ENABLE_AI_FEATURES
// Your AI code here
#else
// Fallback for pattern-only mode
#endif
```

### Restoring AI Features

To restore AI features for development or release:
1. Open Xcode build settings
2. Add `-D ENABLE_AI_FEATURES` to "Other Swift Flags"
3. Clean build folder (⇧⌘K)
4. Rebuild

No code changes needed - everything is already in place!

---

## Copy Button Feedback (RESOLVED - 2025-11-01)

**Issue:** Copy buttons worked but provided no immediate visual feedback.

**Solution Implemented:**
- Button icon changes from "doc.on.doc" to "checkmark" when clicked
- Button text changes from "Copy" to "Copied!" briefly
- Smooth animation (0.2s ease-in-out transition)
- Auto-resets after 0.5 seconds
- **Success banner messages removed** for copy/restore operations (feedback now only on button)

**Affected Buttons:**
- Copy Anonymized Text (middle pane)
- Copy Restored Text (right pane)

**Technical Implementation:**
- Added `@Published` state variables: `justCopiedAnonymized`, `justCopiedRestored`, `justCopiedOriginal`
- Removed `successMessage` assignments from copy/restore functions
- Kept success messages for other operations (analysis complete, custom entity added)

---

## Sidebar Collapse Layout Issue (FIXED - 2025-11-01)

**Issue:** When collapsing the entity sidebar, the entire window layout would distort and resize incorrectly.

**Root Cause:**
- Sidebar was using flexible width constraints (`minWidth`, `idealWidth`, `maxWidth`)
- HSplitView was recalculating layout based on these changing constraints
- Window resizing caused visual distortion

**Solution:**
- Changed to **fixed widths**: 40px (collapsed) and 180px (expanded)
- Removed flexible constraints that were causing layout recalculations
- Added smooth animation between the two fixed sizes

**Code Change:**
```swift
// Before (problematic)
.frame(
    minWidth: isCollapsed ? 40 : 165,
    idealWidth: isCollapsed ? 40 : 180,
    maxWidth: isCollapsed ? 40 : 300
)

// After (fixed)
.frame(maxHeight: .infinity)
.frame(width: isCollapsed ? 40 : 180)
```

**Result:** Sidebar now collapses/expands smoothly without affecting window layout.
