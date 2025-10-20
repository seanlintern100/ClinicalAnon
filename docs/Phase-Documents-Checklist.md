# ClinicalAnon - Phase Documents Checklist
## Action Plan: All Files to Create by Phase

**Organization:** 3 Big Things
**Purpose:** Comprehensive checklist of every file needed for full implementation
**Status:** Planning Document

---

## How to Use This Document

- [ ] = Not started
- [⏳] = In progress
- [✅] = Completed

Each phase lists ALL files that need to be created. Check them off as you complete them.

---

## PHASE 1: Project Setup & Design System

### Project Structure
- [ ] Create Xcode project: `ClinicalAnon.xcodeproj`
- [ ] Set up folder groups in Xcode:
  - [ ] Views/
  - [ ] Views/Components/
  - [ ] ViewModels/
  - [ ] Models/
  - [ ] Services/
  - [ ] Utilities/
  - [ ] Resources/
  - [ ] Resources/Fonts/
  - [ ] Tests/

### Core App Files
- [ ] `ClinicalAnonApp.swift` (App entry point)
  - Main @App structure
  - Window configuration
  - Initial scene setup
  - **Location:** Root of project

### Resources
- [ ] Download Lora font family (from Google Fonts)
  - [ ] Lora-Regular.ttf
  - [ ] Lora-Bold.ttf
  - [ ] Lora-Italic.ttf
- [ ] Download Source Sans 3 font family (from Google Fonts)
  - [ ] SourceSans3-Regular.ttf
  - [ ] SourceSans3-SemiBold.ttf
  - [ ] SourceSans3-Bold.ttf
- [ ] Add fonts to `Resources/Fonts/`
- [ ] Update `Info.plist` with font declarations

### Utilities Files
- [ ] `Utilities/DesignSystem.swift`
  - Colors struct
    - primaryTeal, sage, orange, sand, charcoal, warmWhite
    - Dark mode variants
  - Typography struct
    - title, heading, body, caption
    - Custom font helpers
  - Spacing struct
    - xs, small, medium, large, xlarge, xxlarge
  - CornerRadius struct
    - small, medium, large
  - Shadow struct
    - soft, medium, strong
  - **Lines:** ~200-250

- [ ] `Utilities/AppError.swift`
  - Enum with error cases:
    - ollamaNotInstalled
    - ollamaNotRunning
    - modelNotDownloaded
    - networkError
    - timeoutError
    - invalidResponse
    - parsingError
    - ollamaInstallFailed
    - modelDownloadFailed
  - LocalizedError conformance
  - User-friendly descriptions
  - **Lines:** ~80-100

### Documentation
- [ ] Create `README.md` in project root
  - Project description
  - Setup instructions
  - Development notes

### Verification Files
- [ ] Create simple test view to verify design system
  - Test all colors render
  - Test fonts load correctly
  - Test spacing values
  - Delete after verification

**PHASE 1 DELIVERABLES:** 2 Swift files (DesignSystem.swift, AppError.swift), Fonts integrated, Project compiles

---

## PHASE 2: Setup Flow & Ollama Integration

### Utilities Files
- [ ] `Utilities/SetupManager.swift`
  - SetupState enum
  - @MainActor SetupManager class
  - @Published var state
  - @Published var downloadProgress
  - @Published var downloadStatus
  - Detection methods:
    - isHomebrewInstalled()
    - isOllamaInstalled()
    - isOllamaRunning()
    - isModelDownloaded()
  - Action methods:
    - checkSetup()
    - installOllama()
    - startOllama()
    - downloadModel()
  - Helper methods:
    - executeCommand()
    - parseProgress()
    - startPollingForInstallation()
  - **Lines:** ~300-400

### Views Files
- [ ] `Views/SetupView.swift`
  - Main SetupView struct
  - @StateObject setupManager
  - Switch on setup states
  - Subviews:
    - checkingView
    - readyView
    - needsHomebrewView
    - needsOllamaView
    - needsModelView
    - downloadingView(progress:)
    - startingView
    - errorView(message:)
  - All styled with DesignSystem
  - **Lines:** ~400-500

### Services Files
- [ ] `Services/OllamaService.swift`
  - OllamaServiceProtocol protocol definition
  - OllamaService class
  - Mock mode toggle
  - Properties:
    - baseURL
    - isMockMode
  - Methods:
    - sendRequest(text:systemPrompt:) async throws -> String
    - checkConnection() async throws -> Bool
    - buildRequest()
    - parseMockResponse() (for testing)
  - Error handling
  - URLSession integration
  - **Lines:** ~200-300

### App Entry Updates
- [ ] Update `ClinicalAnonApp.swift`
  - Add @StateObject setupManager
  - Conditional view rendering
  - Window configuration (1200x700)
  - UserDefaults for setup state
  - **Lines:** ~50-80

**PHASE 2 DELIVERABLES:** 3 new files (SetupManager.swift, SetupView.swift, OllamaService.swift), Updated app entry, Setup wizard functional

---

## PHASE 3: Core Data Models

### Models Files
- [ ] `Models/EntityType.swift`
  - EntityType enum
  - Cases: person_client, person_provider, location, organization, date, identifier
  - Codable conformance
  - CaseIterable conformance
  - Computed properties:
    - displayName
    - prefix (CLIENT_, PROVIDER_, etc.)
  - **Lines:** ~40-60

- [ ] `Models/Entity.swift`
  - Entity struct
  - Identifiable conformance (UUID id)
  - Codable conformance
  - Properties:
    - id: UUID
    - original: String
    - replacement: String
    - type: EntityType
    - ranges: [NSRange]
  - Custom Codable implementation for NSRange
  - **Lines:** ~60-80

- [ ] `Models/AnalysisResult.swift`
  - AnalysisResult struct
  - Properties:
    - originalText: String
    - anonymizedText: String
    - entities: [Entity]
    - mapping: [String: String]
    - processingTime: TimeInterval
  - Computed properties:
    - entityCount
    - replacementCount
  - **Lines:** ~30-50

- [ ] `Models/OllamaRequest.swift`
  - OllamaRequest struct
  - Codable conformance
  - Properties:
    - model: String
    - prompt: String
    - stream: Bool
    - options: OllamaOptions?
  - Nested OllamaOptions struct:
    - temperature: Double?
    - num_predict: Int?
  - **Lines:** ~30-40

- [ ] `Models/OllamaResponse.swift`
  - OllamaResponse struct
  - Codable conformance
  - Properties:
    - model: String
    - created_at: String
    - response: String
    - done: Bool
  - LLMAnonymizationResponse struct
  - Properties:
    - anonymized_text: String
    - entities: [LLMEntity]
  - Nested LLMEntity struct:
    - original: String
    - replacement: String
    - type: String
    - positions: [[Int]]
  - **Lines:** ~50-70

**PHASE 3 DELIVERABLES:** 5 new model files, All models Codable, JSON serialization tested

---

## PHASE 4: Business Logic - Services

### Services Files (New)
- [ ] `Services/EntityMapper.swift`
  - EntityMapper class
  - EntityMapperProtocol protocol
  - Properties:
    - Private counters for each entity type (clientCounter, providerCounter, etc.)
    - mappings: [String: String]
  - Methods:
    - getCode(for:type:) -> String
    - reset()
    - currentMappings computed property
  - Counter logic (A, B, C... Z, AA, AB...)
  - Case-insensitive entity matching
  - **Lines:** ~100-150

- [ ] `Services/AnonymizationEngine.swift`
  - AnonymizationEngine class
  - Properties:
    - ollamaService: OllamaServiceProtocol
    - entityMapper: EntityMapper
  - Methods:
    - anonymizeText(_ text:) async throws -> AnalysisResult
  - Private methods:
    - constructSystemPrompt() -> String
    - constructUserPrompt(text:) -> String
    - parseResponse(_ jsonString:) throws -> LLMAnonymizationResponse
    - convertToEntities(_ llmEntities:, in text:) -> [Entity]
    - buildAnalysisResult()
  - Error handling
  - Processing time measurement
  - **Lines:** ~250-350

### Services Files (Updates)
- [ ] Update `Services/OllamaService.swift`
  - Add complete system prompt (from spec section 6.1)
  - Add user prompt template (from spec section 6.2)
  - Implement mock response generator
  - Add request timeout (30 seconds)
  - Add response validation
  - **Additional lines:** ~100-150

### Utilities Files (New)
- [ ] `Utilities/PromptTemplates.swift`
  - Static system prompt (complete text from spec)
  - User prompt template function
  - Te reo Māori handling notes
  - JSON output format specification
  - **Lines:** ~80-120

**PHASE 4 DELIVERABLES:** 2 new service files (EntityMapper, AnonymizationEngine), 1 utility file (PromptTemplates), Updated OllamaService, End-to-end processing working with mocks

---

## PHASE 5: UI Components

### Utilities Files (Extensions)
- [ ] `Utilities/DesignSystem+Buttons.swift`
  - PrimaryButtonStyle struct (ViewModifier)
  - SecondaryButtonStyle struct
  - AccentButtonStyle struct
  - DisabledButtonStyle struct
  - All with hover states
  - **Lines:** ~120-160

- [ ] `Utilities/HighlightHelper.swift`
  - HighlightHelper class (static methods)
  - Methods:
    - createHighlightedText(text:entities:highlightColor:) -> AttributedString
    - applyHighlight(to range:in attributedString:color:)
    - calculateRanges(for entities:) -> [NSRange]
    - mergeOverlappingRanges(_ ranges:) -> [NSRange]
  - NSAttributedString handling
  - Color conversion helpers
  - **Lines:** ~150-200

### Views/Components Files
- [ ] `Views/Components/Card.swift`
  - Card<Content: View> struct
  - @ViewBuilder content parameter
  - DesignSystem styling applied
  - Shadow and corner radius
  - Light/dark mode support
  - **Lines:** ~30-50

- [ ] `Views/Components/StatusIndicator.swift`
  - StatusIndicator struct
  - StatusState enum (ready, processing, error, success)
  - @Binding var state
  - Icon + text display
  - Animated spinner for processing
  - Color coding by state
  - Auto-fade for success
  - **Lines:** ~80-120

- [ ] `Views/Components/HighlightedTextEditor.swift`
  - HighlightedTextEditor struct
  - Wraps NSTextView for AttributedString support
  - @Binding var text: String
  - @Binding var attributedText: AttributedString
  - isReadOnly: Bool parameter
  - Monospace font application
  - Scroll position tracking
  - **Lines:** ~150-200

- [ ] `Views/Components/ActionButton.swift`
  - ActionButton struct
  - Parameters:
    - title: String
    - style: ButtonStyleType enum
    - action: () -> Void
    - isDisabled: Bool
  - Hover state handling
  - Icon support (optional)
  - **Lines:** ~60-90

**PHASE 5 DELIVERABLES:** 2 utility extensions, 4 component files, All components previewed and styled

---

## PHASE 6: Main App View

### ViewModels Files
- [ ] `ViewModels/AppViewModel.swift`
  - @MainActor AppViewModel class
  - ObservableObject conformance
  - @Published properties:
    - originalText: String
    - anonymizedText: String
    - isProcessing: Bool
    - errorMessage: String?
    - entities: [Entity]
    - isOriginalTextReadOnly: Bool
    - statusState: StatusState
  - Private properties:
    - engine: AnonymizationEngine
    - entityMapper: EntityMapper
  - Methods:
    - init(engine:)
    - analyze() async
    - clearAll()
    - copyToClipboard()
    - handleError(_ error:)
  - State management logic
  - **Lines:** ~200-300

### Views Files
- [ ] `Views/ContentView.swift`
  - ContentView struct
  - @StateObject viewModel
  - @State for highlighting
  - Body:
    - HSplitView (two panes)
    - Left pane (original text)
    - Right pane (anonymized text)
    - Button toolbar (HStack)
    - Status indicator
    - Warning banner
  - Private subviews:
    - leftPaneView
    - rightPaneView
    - buttonToolbar
    - warningBanner
  - Keyboard shortcuts
  - Highlight application logic
  - **Lines:** ~300-400

### Views/Components Files (Updates)
- [ ] Update `Views/Components/HighlightedTextEditor.swift`
  - Add manual edit detection
  - Add highlight removal on edit
  - Add placeholder text support
  - **Additional lines:** ~50-80

**PHASE 6 DELIVERABLES:** 1 ViewModel file, 1 main view file, Updated text editor component, Full app workflow functional

---

## PHASE 7: Real Ollama Integration & Prompt Engineering

### Services Files (Updates)
- [ ] Update `Services/OllamaService.swift`
  - Disable mock mode by default
  - Add real Ollama connection
  - Add retry logic
  - Enhanced error messages
  - **Additional lines:** ~50-100

### Utilities Files (Updates)
- [ ] Update `Utilities/PromptTemplates.swift`
  - Refine system prompt based on testing
  - Add example-based prompting
  - Add edge case handling instructions
  - **Additional lines:** ~50-80

### Testing Files
- [ ] Create `Tests/SampleClinicalNotes.swift`
  - 5-10 realistic clinical note examples
  - Various scenarios (single client, multiple clients, providers, Māori names)
  - Expected entity detection for each
  - **Lines:** ~200-300

**PHASE 7 DELIVERABLES:** Updated OllamaService and PromptTemplates, Sample notes for testing, Real LLM integration working

---

## PHASE 8: Polish & Edge Cases

### Utilities Files (New)
- [ ] `Utilities/TextValidator.swift`
  - Validate text length
  - Check for special characters
  - Sanitize input
  - **Lines:** ~50-80

- [ ] `Utilities/ClipboardManager.swift`
  - Enhanced clipboard operations
  - Format preservation options
  - Error handling for clipboard access
  - **Lines:** ~40-60

### Views Files (Updates)
- [ ] Update `Views/ContentView.swift`
  - Add loading animations
  - Add empty state guidance
  - Add tooltips
  - Improve error display
  - **Additional lines:** ~80-120

- [ ] Update `Views/SetupView.swift`
  - Add accessibility labels
  - Add VoiceOver support
  - Improve error recovery
  - **Additional lines:** ~50-80

### Services Files (Updates)
- [ ] Update `Services/AnonymizationEngine.swift`
  - Add text chunking for very long notes
  - Add memory management
  - Add progress callbacks
  - **Additional lines:** ~100-150

**PHASE 8 DELIVERABLES:** 2 new utility files, Updated views and services, All edge cases handled

---

## PHASE 9: Testing & Validation

### Testing Files
- [ ] `Tests/OllamaServiceTests.swift`
  - Test connection checking
  - Test request building
  - Test response parsing
  - Test error handling
  - **Lines:** ~150-200

- [ ] `Tests/EntityMapperTests.swift`
  - Test consistency logic
  - Test counter incrementing
  - Test reset functionality
  - **Lines:** ~100-150

- [ ] `Tests/AnonymizationEngineTests.swift`
  - Test end-to-end processing
  - Test with mock responses
  - Test error propagation
  - **Lines:** ~150-200

- [ ] `Tests/HighlightHelperTests.swift`
  - Test range calculations
  - Test highlight application
  - Test overlapping ranges
  - **Lines:** ~80-120

### Documentation Files
- [ ] `docs/Testing-Scenarios.md`
  - All manual test scenarios
  - Expected outcomes
  - Edge cases to verify
  - **Lines:** Text document

- [ ] `docs/Known-Issues.md`
  - Document any known limitations
  - Workarounds
  - Future improvements
  - **Lines:** Text document

**PHASE 9 DELIVERABLES:** 4 test files, 2 documentation files, All tests passing

---

## PHASE 10: Deployment Preparation

### Resources Files
- [ ] Create app icon set
  - [ ] AppIcon.appiconset/
  - Icons at all required sizes
  - macOS-specific icon design

- [ ] `Resources/Assets.xcassets`
  - Color assets
  - Image assets
  - App icon

### Documentation Files
- [ ] `USER-GUIDE.md`
  - Installation instructions
  - Setup wizard walkthrough
  - How to use the app
  - Troubleshooting
  - Privacy & security notes
  - **Lines:** Text document

- [ ] `CHANGELOG.md`
  - Version 1.0 release notes
  - Features list
  - Known limitations
  - **Lines:** Text document

- [ ] `LICENSE.md`
  - Choose license
  - Copyright notice
  - **Lines:** Text document

### Build Configuration
- [ ] Update `Info.plist`
  - App version
  - Copyright info
  - Minimum OS version
  - Required device capabilities

- [ ] Configure code signing
  - Developer ID certificate
  - Provisioning profile
  - Entitlements file

### Distribution Files
- [ ] Create DMG installer (macOS)
- [ ] Create simple installer README
- [ ] Notarization submission

**PHASE 10 DELIVERABLES:** App icon, Complete documentation, Signed and notarized build, Ready for distribution

---

## Complete File Count Summary

### Swift Files
- **App Entry:** 1 file (ClinicalAnonApp.swift)
- **Models:** 5 files (Entity, EntityType, AnalysisResult, OllamaRequest, OllamaResponse)
- **Views:** 2 main files (ContentView, SetupView)
- **Views/Components:** 4 files (Card, StatusIndicator, HighlightedTextEditor, ActionButton)
- **ViewModels:** 1 file (AppViewModel)
- **Services:** 3 files (OllamaService, EntityMapper, AnonymizationEngine)
- **Utilities:** 7 files (DesignSystem, DesignSystem+Buttons, AppError, HighlightHelper, SetupManager, PromptTemplates, TextValidator, ClipboardManager)
- **Tests:** 4 files (OllamaServiceTests, EntityMapperTests, AnonymizationEngineTests, HighlightHelperTests)

**Total Swift Files: ~27**

### Resource Files
- **Fonts:** 6 font files
- **Assets:** Icon set, colors, images
- **Config:** Info.plist, entitlements

### Documentation Files
- **Planning:** 3 files (this checklist, Implementation-Plan, spec)
- **User-facing:** 4 files (README, USER-GUIDE, CHANGELOG, LICENSE)
- **Development:** 2 files (Testing-Scenarios, Known-Issues)

**Total Documentation: ~9**

---

## File Creation Priority

### Critical Path (Must complete in order)
1. DesignSystem.swift → Needed by all views
2. AppError.swift → Needed by all services
3. All Models → Needed by services
4. OllamaService → Needed by engine
5. EntityMapper → Needed by engine
6. AnonymizationEngine → Needed by ViewModel
7. Components → Needed by main views
8. ViewModel → Needed by ContentView
9. ContentView → Main app interface

### Can be developed in parallel
- SetupManager + SetupView (independent of main app)
- HighlightHelper (independent utility)
- Tests (after corresponding implementation)

---

## Progress Tracking

Use this checklist actively during development. Update status as files are completed:
- Check off files as completed
- Note any deviations or changes needed
- Add any additional files discovered during implementation

---

*This is a living checklist. Update as implementation progresses.*
