# ClinicalAnon - Implementation Plan
## Clinical Text Anonymization Tool for macOS

**Organization:** 3 Big Things
**Version:** 1.0
**Plan Created:** October 2025
**Status:** Ready for Development

---

## Implementation Philosophy

### Core Principles
✅ **Get it right the first time** - Thorough implementation at each stage
✅ **Phase-by-phase validation** - Verify each stage works before proceeding
✅ **No revisiting foundations** - Complete design system and architecture from start
✅ **Manual testing focus** - Developer tests at each phase, minimal automated tests for MVP

### Technical Decisions
- **Target OS:** macOS 13 (Ventura) or later
- **Xcode Version:** Xcode 15+
- **Swift Version:** Swift 5.9+
- **UI Framework:** SwiftUI (native macOS)
- **Fonts:** Custom fonts (Lora + Source Sans 3) from start
- **Distribution:** Direct download (simpler code signing)
- **Ollama:** Integration built with mock mode first, real integration in later phase

---

## Phase-by-Phase Implementation Plan

### **PHASE 1: Project Setup & Design System**
**Duration:** Day 1
**Status:** Ready to Start

#### Goals
- Modern Xcode project configured correctly
- Complete design system with brand fonts
- Foundation that won't need revisiting

#### Tasks
1. Create Xcode project
   - Product Name: ClinicalAnon
   - Organization: 3 Big Things
   - Interface: SwiftUI
   - Language: Swift
   - Target: macOS 13.0+
   - Architecture: Apple Silicon primary, Intel compatible

2. Set up project folder structure
   ```
   ClinicalAnon/
   ├── ClinicalAnonApp.swift
   ├── Views/
   ├── ViewModels/
   ├── Models/
   ├── Services/
   ├── Utilities/
   ├── Resources/
   └── Tests/
   ```

3. Download and integrate fonts
   - Download **Lora** (serif) from Google Fonts
   - Download **Source Sans 3** (sans-serif) from Google Fonts
   - Add font files to Resources/Fonts/
   - Update Info.plist with font declarations
   - Test font rendering in preview

4. Implement DesignSystem.swift (Utilities/)
   - Colors: Teal, Sage, Orange, Sand, Charcoal, Warm White
   - Typography: Title, heading, body, caption styles with custom fonts
   - Spacing: xs, small, medium, large, xlarge, xxlarge
   - Corner radius standards
   - Shadow definitions
   - Button styles as ViewModifiers

5. Create AppError.swift (Utilities/)
   - All error types defined per spec
   - LocalizedError conformance
   - User-friendly error messages

#### Verification Checklist
- [ ] Project builds without errors
- [ ] Custom fonts render in SwiftUI preview
- [ ] DesignSystem colors display correctly in light/dark mode
- [ ] Can create views using DesignSystem constants
- [ ] AppError types can be thrown and caught

#### Deliverables
- Empty app that compiles
- Complete design system in place
- All foundations ready for Phase 2

---

### **PHASE 2: Setup Flow & Ollama Integration**
**Duration:** Days 2-3
**Status:** Pending Phase 1 completion

#### Goals
- Working setup wizard with all states
- Ollama detection and installation flow
- HTTP communication foundation ready

#### Tasks
1. Implement SetupManager.swift (Utilities/)
   - `isHomebrewInstalled()` - Check for brew
   - `isOllamaInstalled()` - Check for Ollama binary
   - `isOllamaRunning()` - Ping localhost:11434
   - `isModelDownloaded()` - Check for llama3.1:8b
   - `installOllama()` - Trigger Terminal with command
   - `downloadModel()` - Execute ollama pull with progress
   - `startOllama()` - Launch ollama serve
   - `checkSetup()` - Main orchestration method
   - State management with @Published properties

2. Create SetupView.swift (Views/)
   - Welcome screen with app intro
   - Needs Homebrew screen (copy command option)
   - Needs Ollama screen (auto-install + manual options)
   - Model download screen with progress bar
   - Ready state confirmation
   - Error states with helpful messages
   - All screens using DesignSystem styles

3. Implement OllamaService.swift (Services/)
   - Protocol definition: OllamaServiceProtocol
   - HTTP POST to localhost:11434/api/generate
   - Request building (model, prompt, options)
   - Response parsing (JSON → OllamaResponse)
   - Timeout handling (30 seconds)
   - Connection checking
   - **Mock mode toggle** for testing without Ollama
   - Error types (network, timeout, invalid response)

4. Update ClinicalAnonApp.swift
   - @StateObject for SetupManager
   - Conditional view rendering:
     ```swift
     if setupManager.state == .ready {
         ContentView()
     } else {
         SetupView()
     }
     ```
   - UserDefaults persistence for setup completion
   - Window configuration (size, title)

#### Verification Checklist
- [ ] Setup wizard displays all states correctly
- [ ] Can detect Homebrew/Ollama presence
- [ ] Copy to clipboard works for manual install
- [ ] Progress indicators animate properly
- [ ] Error messages are clear and helpful
- [ ] OllamaService can mock responses
- [ ] App transitions from setup to main view when ready

#### Deliverables
- Complete setup wizard working end-to-end
- Ollama detection and guidance functional
- HTTP service foundation ready

---

### **PHASE 3: Core Data Models**
**Duration:** Day 4
**Status:** Pending Phase 2 completion

#### Goals
- Complete data layer defined
- All models Codable and validated
- JSON serialization working

#### Tasks
1. Create Entity.swift (Models/)
   ```swift
   struct Entity: Identifiable, Codable {
       let id: UUID
       let original: String
       let replacement: String
       let type: EntityType
       let ranges: [NSRange]
   }
   ```

2. Create EntityType.swift (Models/)
   ```swift
   enum EntityType: String, Codable, CaseIterable {
       case person_client
       case person_provider
       case location
       case organization
       case date
       case identifier

       var displayName: String { ... }
       var prefix: String { ... } // "CLIENT_", "PROVIDER_", etc.
   }
   ```

3. Create AnalysisResult.swift (Models/)
   ```swift
   struct AnalysisResult {
       let originalText: String
       let anonymizedText: String
       let entities: [Entity]
       let mapping: [String: String]
       let processingTime: TimeInterval

       var entityCount: Int { ... }
       var replacementCount: Int { ... }
   }
   ```

4. Create OllamaRequest.swift (Models/)
   ```swift
   struct OllamaRequest: Codable {
       let model: String
       let prompt: String
       let stream: Bool
       let options: OllamaOptions?

       struct OllamaOptions: Codable {
           let temperature: Double?
           let num_predict: Int?
       }
   }
   ```

5. Create OllamaResponse.swift (Models/)
   ```swift
   struct OllamaResponse: Codable {
       let model: String
       let created_at: String
       let response: String
       let done: Bool
   }

   struct LLMAnonymizationResponse: Codable {
       let anonymized_text: String
       let entities: [LLMEntity]

       struct LLMEntity: Codable {
           let original: String
           let replacement: String
           let type: String
           let positions: [[Int]]
       }
   }
   ```

#### Verification Checklist
- [ ] All models compile without errors
- [ ] Can encode models to JSON
- [ ] Can decode models from JSON
- [ ] Test with sample JSON from spec
- [ ] NSRange handling works correctly
- [ ] Entity types return correct prefixes

#### Deliverables
- Complete data model layer
- JSON serialization validated
- Ready for business logic integration

---

### **PHASE 4: Business Logic - Services**
**Duration:** Days 5-6
**Status:** Pending Phase 3 completion

#### Goals
- Core anonymization logic complete
- Entity mapping consistency working
- End-to-end processing functional (with mocks)

#### Tasks
1. Complete OllamaService.swift (Services/)
   - Full request/response cycle
   - System prompt construction (from spec section 6.1)
   - User prompt template (from spec section 6.2)
   - Response validation (check for valid JSON)
   - Error handling for all cases
   - Mock mode returns realistic test data
   - Timeout implementation (30s)

2. Implement EntityMapper.swift (Services/)
   ```swift
   class EntityMapper {
       private var clientCounter: Int = 0
       private var providerCounter: Int = 0
       private var locationCounter: Int = 0
       // ... other counters

       private var mappings: [String: String] = [:]

       func getCode(for entity: String, type: EntityType) -> String
       func reset()
       var currentMappings: [String: String] { mappings }
   }
   ```
   - Consistency tracking (same entity → same code)
   - Counter management (A, B, C... then AA, AB, etc.)
   - Reset functionality
   - Case-insensitive matching with trim

3. Create AnonymizationEngine.swift (Services/)
   ```swift
   class AnonymizationEngine {
       private let ollamaService: OllamaServiceProtocol
       private let entityMapper: EntityMapper

       func anonymizeText(_ text: String) async throws -> AnalysisResult
   }
   ```
   - Orchestrates OllamaService + EntityMapper
   - Sends text with prompts to LLM
   - Parses JSON response into LLMAnonymizationResponse
   - Converts to Entity objects with ranges
   - Uses EntityMapper for consistency
   - Builds final AnalysisResult
   - Error handling and validation
   - Measures processing time

#### Verification Checklist
- [ ] Can process sample clinical text
- [ ] EntityMapper returns consistent codes (same entity → same code)
- [ ] Counter increments correctly (CLIENT_A, CLIENT_B, etc.)
- [ ] Reset clears all mappings and counters
- [ ] AnonymizationEngine returns valid AnalysisResult
- [ ] Mock mode produces realistic anonymized text
- [ ] Error handling catches malformed JSON
- [ ] Processing time is measured

#### Deliverables
- Fully functional business logic layer
- Can process text end-to-end (with mocked LLM)
- Ready for UI integration

---

### **PHASE 5: UI Components**
**Duration:** Days 7-8
**Status:** Pending Phase 4 completion

#### Goals
- Reusable, styled components ready
- Consistent look across app
- Text highlighting system working

#### Tasks
1. Create button styles (Utilities/DesignSystem+Buttons.swift)
   - PrimaryButtonStyle (Teal background, white text)
   - SecondaryButtonStyle (Outlined charcoal border)
   - AccentButtonStyle (Orange background, white text)
   - DisabledButtonStyle (Muted appearance)
   - Hover states for all

2. Create Card.swift (Views/Components/)
   - White/sand background card
   - Padding and corner radius from DesignSystem
   - Shadow application
   - Content slot (ViewBuilder)

3. Create StatusIndicator.swift (Views/Components/)
   - States: Ready, Processing, Error, Success
   - Color coding (green, orange, red)
   - Animated spinner for processing
   - Auto-fade for success state

4. Implement HighlightHelper.swift (Utilities/)
   ```swift
   class HighlightHelper {
       static func createHighlightedText(
           text: String,
           entities: [Entity],
           highlightColor: Color
       ) -> AttributedString

       static func applyHighlight(
           to range: NSRange,
           in attributedString: inout AttributedString,
           color: Color
       )
   }
   ```
   - NSAttributedString creation
   - Yellow highlighting (30% opacity)
   - Range calculations and validation
   - Handles overlapping ranges
   - Font preservation

5. Create custom TextEditor wrapper (Views/Components/HighlightedTextEditor.swift)
   - Supports AttributedString for highlighting
   - Read-only mode toggle
   - Scroll position tracking
   - Monospace font application

#### Verification Checklist
- [ ] All button styles render correctly
- [ ] Buttons show proper hover states
- [ ] Card component displays with shadow
- [ ] StatusIndicator shows all states
- [ ] Processing spinner animates
- [ ] HighlightHelper creates yellow highlights
- [ ] Highlights appear in correct positions
- [ ] TextEditor shows highlighted text
- [ ] Read-only mode prevents editing

#### Deliverables
- Complete UI component library
- Highlighting system functional
- Ready for main view integration

---

### **PHASE 6: Main App View**
**Duration:** Days 9-10
**Status:** Pending Phase 5 completion

#### Goals
- Two-pane interface fully functional
- Complete user workflow working
- Highlighting in both panes

#### Tasks
1. Create AppViewModel.swift (ViewModels/)
   ```swift
   @MainActor
   class AppViewModel: ObservableObject {
       @Published var originalText: String = ""
       @Published var anonymizedText: String = ""
       @Published var isProcessing: Bool = false
       @Published var errorMessage: String? = nil
       @Published var entities: [Entity] = []
       @Published var isOriginalTextReadOnly: Bool = false

       private let engine: AnonymizationEngine

       func analyze() async
       func clearAll()
       func copyToClipboard()
   }
   ```
   - State management for entire app
   - Async analyze operation
   - Error handling with user feedback
   - Entity storage for highlighting
   - Clipboard operations

2. Implement ContentView.swift (Views/)
   - HSplitView for two-pane layout
   - Left pane: Original text editor
     - Editable before analysis
     - Read-only after analysis
     - Yellow highlights on detected entities
     - Placeholder text when empty
   - Right pane: Anonymized text editor
     - Empty until analysis
     - Always editable
     - Yellow highlights on replacement codes
     - Manual edit detection
   - Button toolbar:
     - Analyze button (disabled when empty)
     - Clear All button (always enabled)
     - Copy Anonymized button (disabled when empty)
   - Status indicator (bottom right)
   - Warning banner (bottom)
     - "⚠️ Manual edits are not tracked. Review carefully before sharing."

3. Wire up highlighting
   - Apply HighlightHelper to both panes
   - Update highlights when entities change
   - Remove highlights on manual edit (right pane)
   - Maintain scroll sync where possible

4. Add keyboard shortcuts
   - Cmd+Shift+C for Copy Anonymized
   - Cmd+K for Clear All
   - Cmd+R for Analyze (when ready)

#### Verification Checklist
- [ ] Window opens at correct size (1200x700)
- [ ] Two panes split evenly
- [ ] Can paste text into left pane
- [ ] Analyze button triggers processing
- [ ] Both panes show highlights after analysis
- [ ] Left pane becomes read-only after analysis
- [ ] Right pane remains editable
- [ ] Manual edits remove highlights in edited areas
- [ ] Copy button copies to clipboard
- [ ] Clear All resets everything
- [ ] Status indicator shows correct states
- [ ] Warning banner always visible
- [ ] Keyboard shortcuts work

#### Deliverables
- Fully functional main application view
- Complete workflow working end-to-end
- Ready for real Ollama integration

---

### **PHASE 7: Real Ollama Integration & Prompt Engineering**
**Duration:** Days 11-12
**Status:** Pending Phase 6 completion

#### Goals
- Real LLM integration working
- Prompts optimized for accuracy
- Entity detection validated

#### Tasks
1. Update OllamaService to disable mock mode
2. Implement complete system prompt (from spec section 6.1)
3. Test with real Ollama responses
4. Validate entity detection accuracy
5. Refine prompts based on test results
6. Handle edge cases (malformed JSON, partial responses)
7. Test with various clinical note samples

#### Verification Checklist
- [ ] Can connect to Ollama successfully
- [ ] LLM returns valid JSON
- [ ] Entity detection is accurate
- [ ] Consistency works (same entity → same code)
- [ ] Clinical context preserved
- [ ] Te reo Māori names handled correctly
- [ ] Error handling works for LLM failures

---

### **PHASE 8: Polish & Edge Cases**
**Duration:** Days 13-14
**Status:** Pending Phase 7 completion

#### Goals
- Handle all edge cases
- Performance optimization
- UI/UX refinements

#### Tasks
1. Edge case handling:
   - Very long texts (>10,000 words)
   - Empty responses from LLM
   - Network interruptions
   - Ollama stops during processing
   - Special characters in text
   - Multiple clients in one note

2. Performance optimization:
   - Lazy loading for long texts
   - Efficient highlighting for many entities
   - Memory management

3. UI polish:
   - Loading states and animations
   - Error message refinements
   - Accessibility improvements
   - Dark mode verification

4. User experience:
   - Helpful tooltips
   - Empty state guidance
   - Processing time display

---

### **PHASE 9: Testing & Validation**
**Duration:** Day 15
**Status:** Pending Phase 8 completion

#### Manual Testing Scenarios
1. **Happy Path:**
   - Paste note → Analyze → Review → Copy → Clear

2. **Setup Flow:**
   - Test on machine without Ollama
   - Verify install guidance
   - Test model download

3. **Error Handling:**
   - Disconnect from internet during analysis
   - Stop Ollama during processing
   - Paste malformed text
   - Very long text (stress test)

4. **Consistency:**
   - Same name appears 10+ times
   - Multiple clients in one note
   - Ambiguous names (Dawn = name vs time)

5. **Clinical Accuracy:**
   - Test with sample clinical notes
   - Verify clinical context preserved
   - Check date handling (specific vs relative)
   - Validate Māori name handling

---

### **PHASE 10: Deployment Preparation**
**Duration:** Day 16
**Status:** Pending Phase 9 completion

#### Tasks
1. Code signing for direct distribution
2. Create app icon and assets
3. Build and archive for distribution
4. Create simple user guide (README.pdf)
5. Test on clean macOS install
6. Package for distribution

---

## Success Criteria

### Phase Completion Requirements
Each phase must meet ALL verification checklist items before proceeding to next phase.

### Final MVP Requirements
- [ ] App installs and runs on macOS 13+
- [ ] Setup wizard guides user through Ollama installation
- [ ] Can anonymize clinical text with LLM assistance
- [ ] Highlighting shows detected/replaced entities
- [ ] Consistent entity mapping within session
- [ ] Clinical context preserved
- [ ] Copy to clipboard works
- [ ] No data written to disk
- [ ] Clear error messages
- [ ] Stable and responsive UI

---

## Risk Mitigation

### Technical Risks
1. **Ollama integration complexity**
   - Mitigation: Mock mode allows UI development in parallel

2. **LLM prompt engineering**
   - Mitigation: Detailed prompt spec provided, iterative testing

3. **Text highlighting performance**
   - Mitigation: Use native AttributedString, optimize for large texts

4. **Setup wizard complexity**
   - Mitigation: Phase 2 dedicated to getting this right

### Project Risks
1. **Scope creep**
   - Mitigation: Strict phase boundaries, no additions until Phase 10

2. **Phase validation skipped**
   - Mitigation: Explicit verification checklists per phase

---

## Communication & Progress Tracking

### Phase Completion Protocol
1. Complete all tasks in phase
2. Run through verification checklist
3. Manual testing by developer
4. Document any issues or deviations
5. Explicit approval to proceed to next phase

### Progress Tracking
- Use TodoWrite tool for granular task tracking
- Update this document with completion dates
- Note any deviations or learnings

---

## Next Steps

**IMMEDIATE:** Begin Phase 1 - Project Setup & Design System

**ON DECK:** Phase 2 - Setup Flow & Ollama Integration (awaiting Phase 1 completion)

---

*This implementation plan is a living document and will be updated as phases complete.*
