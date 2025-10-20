# ClinicalAnon - Complete Application Specification
## Clinical Text Anonymization Tool for macOS

**Organization:** 3 Big Things  
**Version:** 1.0  
**Date:** October 2025  
**Document Status:** Ready for Development

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Critical Decisions & Requirements](#2-critical-decisions--requirements)
3. [Functional Specification](#3-functional-specification)
4. [Technical Architecture](#4-technical-architecture)
5. [Ollama Integration Strategy](#5-ollama-integration-strategy)
6. [LLM Prompt Engineering](#6-llm-prompt-engineering)
7. [Development Standards](#7-development-standards)
8. [Brand Integration & Design System](#8-brand-integration--design-system)
9. [Implementation Guide](#9-implementation-guide)
10. [Testing & Validation](#10-testing--validation)
11. [Security & Privacy](#11-security--privacy)
12. [Deployment & User Guide](#12-deployment--user-guide)

---

## 1. Executive Summary

### Purpose
ClinicalAnon is a macOS-native application designed for psychology and wellbeing practitioners to anonymize clinical notes before sharing for case discussions, supervision, or research purposes. The tool prioritizes privacy, accuracy, and clinical context preservation.

### Core Value Proposition
- **100% local processing** - No cloud uploads, no internet required after setup
- **AI-assisted with human oversight** - LLM detects entities, practitioner reviews before applying
- **Clinical context preserved** - Replaces identifying information while maintaining therapeutic meaning
- **New Zealand cultural competence** - Handles te reo Māori names and NZ-specific contexts appropriately

### Key Technical Approach
- **Platform:** Native macOS (SwiftUI) targeting Apple Silicon
- **LLM:** Ollama running Llama 3.1 8B locally
- **Architecture:** MVVM with clear separation of concerns
- **Privacy Model:** Nothing ever written to disk; all processing in-memory only

### User Workflow (5 Steps)
1. Paste clinical text into left pane
2. Click "Analyze" button
3. Review highlighted detections in original text
4. Edit anonymized version if needed (right pane)
5. Copy anonymized text to clipboard

---

## 2. Critical Decisions & Requirements

### 2.1 Consistency Model

**Decision:** Same entity always maps to same code within one session

**Implementation:**
- "Jane Smith" first detected → becomes `[CLIENT_A]`
- All subsequent mentions of "Jane Smith" → also become `[CLIENT_A]`
- Counter resets when user clicks "Clear All" or closes app
- Separate counters for different entity types (CLIENT_, PROVIDER_, LOCATION_, etc.)

**Rationale:** Maintains clinical readability while ensuring consistent anonymization.

---

### 2.2 User Control & Workflow

**Decision:** Review-first with explicit "Analyze" button (not automatic)

**Workflow:**
1. User pastes text → left pane shows original (editable)
2. User clicks "Analyze" → app sends to LLM
3. Both panes show highlighted versions
4. Left pane becomes read-only (shows what was detected)
5. Right pane remains editable (user can modify output)
6. User reviews, edits if needed, then copies result

**Rationale:** Clinical governance requires human review before applying changes. No auto-anonymization ensures practitioner oversight.

---

### 2.3 Persistence Model

**Decision:** Nothing ever saved to disk - pure in-memory processing

**Implementation:**
- Original text: Held only in RAM while app open
- Anonymized text: Held only in RAM while app open
- Entity mappings: Held in @StateObject during session
- On app quit: All memory automatically cleared (standard Swift behavior)
- No temp files, no logs, no cache files ever created

**Rationale:** Maximum privacy for sensitive health information. No risk of data leakage via file system.

---

### 2.4 Replacement Strategy

**Decision:** Generic standardized codes (Option A)

**Entity Types & Replacement Codes:**

| Entity Type | Detection Examples | Replacement Code |
|-------------|-------------------|------------------|
| **Person (Client)** | Jane Smith, Aroha, John | [CLIENT_A], [CLIENT_B], [CLIENT_C]... |
| **Person (Provider)** | Dr. Wilson, Sarah (psychologist) | [PROVIDER_A], [PROVIDER_B]... |
| **Location** | Queen Street, Hamilton, Christchurch | [LOCATION_A], [LOCATION_B]... |
| **Organization** | Kāinga Ora, Middlemore Hospital | [ORGANIZATION_A], [ORGANIZATION_B]... |
| **Date** | 15 March 2024, born 1985 | [DATE_A], [DATE_B]... |
| **Identifier** | NHI ABC1234, 021-555-1234 | [ID_A], [ID_B]... |

**Special Handling:**
- Relative timeframes preserved: "early 2024" stays as "early 2024"
- Clinical context preserved: "34-year-old female" stays as "34-year-old female"
- General locations preserved: "rural area" stays as "rural area"

**Rationale:** Clear that text is anonymized, no risk of accidentally creating a real person's name, consistent and unambiguous.

---

### 2.5 Scope

**Decision:** Single note at a time (v1)

**Limitations:**
- One text input at a time
- No batch processing
- No file upload (paste only)
- No persistent projects or saved sessions

**Future Enhancement Path (v2+):**
- Batch processing multiple notes
- Consistent entity mapping across multiple documents
- Import/export functionality with warnings

**Rationale:** Simplicity for MVP; most use cases are single-note anonymization for immediate sharing.

---

### 2.6 Editing Capability

**Decision:** Anonymized text pane is fully editable after analysis

**Behavior:**
- User can modify any text in right pane after analysis
- Manual edits remove highlighting from edited portions (visual indicator)
- No validation of manual edits (trusts practitioner judgment)
- Warning displayed: "Manual edits are not tracked - review carefully before sharing"

**Rationale:** Practitioners need flexibility to correct LLM errors or refine output. Professional responsibility model.

---

### 2.7 Highlighting System

**Decision:** Simple yellow highlighting (Option A)

**Implementation:**
- All detected/replaced entities highlighted in yellow with 30% opacity
- Left pane: Highlights original detected text
- Right pane: Highlights replacement codes
- Highlights persist until "Clear All" clicked
- No category-based colors (simpler, less cognitive load)
- No tooltips or hover states (cleaner UI)

**Rationale:** Clear visual feedback without overwhelming the practitioner. Focus on review, not categorization.

---

## 3. Functional Specification

### 3.1 Application Overview

**App Name:** ClinicalAnon  
**Tagline:** "Privacy-first clinical text anonymization"  
**Target Users:** Psychologists, therapists, counselors, clinical supervisors  
**Primary Use Cases:**
1. Preparing case notes for clinical supervision
2. Sharing examples in training/teaching contexts
3. Creating de-identified content for research discussions
4. Preparing reports for case reviews or multi-disciplinary teams

---

### 3.2 User Interface Requirements

#### Main Window Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│  ClinicalAnon                                              [● ● ●]   │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌───────────────────────────────┬────────────────────────────────┐ │
│  │  Original Text                │  Anonymized Text               │ │
│  │  (paste clinical note here)   │  (review and edit here)        │ │
│  │                               │                                │ │
│  │  [Text content area with      │  [Text content area with       │ │
│  │   yellow highlighting after   │   yellow highlighting after    │ │
│  │   analysis, becomes read-only │   analysis, remains editable   │ │
│  │   after "Analyze" clicked]    │   throughout]                  │ │
│  │                               │                                │ │
│  │  [scrollable, monospace font  │  [scrollable, monospace font   │ │
│  │   for clinical notes]         │   for consistency]             │ │
│  │                               │                                │ │
│  │                               │                                │ │
│  └───────────────────────────────┴────────────────────────────────┘ │
│                                                                       │
│  [Analyze]  [Clear All]  [Copy Anonymized]           Status: Ready  │
│                                                                       │
│  ⚠️ Manual edits are not tracked. Review carefully before sharing.   │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

**Window Specifications:**
- Default size: 1200 × 700 pixels
- Minimum size: 900 × 600 pixels
- Resizable: Yes, maintains 50/50 split between panes
- Dark mode: Fully supported (colors adapt automatically)

---

### 3.3 Detailed Component Requirements

#### FR-1: Text Input Pane (Left)

**Behavior - Before Analysis:**
- Accepts pasted text (Cmd+V or Edit menu)
- Supports rich text paste (strips formatting, keeps plain text)
- Displays text in monospace font for readability
- Fully editable until "Analyze" clicked
- Scrollable for long documents
- No character limit (practical max ~10,000 words)

**Behavior - After Analysis:**
- Becomes read-only (prevents accidental editing of original)
- Shows yellow highlights on detected entities
- Can be cleared with "Clear All" button
- Background color changes subtly to indicate read-only state

**Visual Feedback:**
- Empty state: Light placeholder text "Paste clinical text here..."
- With content: Standard monospace text (#2E2E2E on #FAF7F4)
- After analysis: Subtle teal border to indicate read-only

---

#### FR-2: Anonymized Output Pane (Right)

**Behavior:**
- Initially empty until "Analyze" clicked
- After analysis: Shows anonymized version with highlights
- Always editable (user can refine output)
- Highlights show replacement codes in yellow
- Manual edits remove highlighting from that text (visual indicator of changes)
- Scrollable, syncs scroll position with left pane when possible

**Visual Feedback:**
- Empty state: Grayed out with text "Click 'Analyze' to generate anonymized version"
- After analysis: Active with highlighted replacements
- During manual edit: Edited portions lose highlight, indicating user modification

---

#### FR-3: Analyze Button

**Behavior:**
- **Disabled when:** Left pane is empty
- **Enabled when:** Text present in left pane
- **On click:**
  1. Validates text is present
  2. Changes to "Analyzing..." with spinner
  3. Sends text to Ollama via OllamaService
  4. Parses LLM response
  5. Updates both panes with highlights
  6. Returns to "Analyze" state (allowing re-analysis if needed)
  7. Left pane becomes read-only

**Error Handling:**
- If Ollama not running: Shows alert "Ollama service not detected. Please start Ollama."
- If timeout (>30 seconds): Shows alert "Analysis timed out. Please try again with shorter text."
- If invalid response: Shows alert "Could not process text. Please try again."

**Visual Design:**
- Default state: Teal (#0A6B7C) background, white text
- Hover state: Darker teal (#045563)
- Processing state: Orange (#E68A2E) with spinner icon
- Disabled state: Light gray (#F5F5F5) with gray text

---

#### FR-4: Clear All Button

**Behavior:**
- **Always enabled** (even with empty panes)
- **On click:**
  1. Clears both text panes
  2. Resets entity mapping (CLIENT_A counter starts from A again)
  3. Removes all highlights
  4. Left pane becomes editable again
  5. Right pane returns to empty state
  6. Resets "Analyze" button to enabled if text present

**Confirmation:**
- No confirmation dialog (quick reset is valuable workflow)
- Cmd+Z undo not supported (privacy feature - no history)

**Visual Design:**
- Secondary button style: Outlined with charcoal border (#2E2E2E)
- Hover: Light sage background (#A9C1B5)

---

#### FR-5: Copy Anonymized Button

**Behavior:**
- **Disabled when:** Right pane is empty
- **Enabled when:** Anonymized text present
- **On click:**
  1. Copies entire content of right pane to system clipboard
  2. Shows brief success message: "Copied to clipboard" (2 second fade)
  3. Includes any manual edits user made

**Keyboard Shortcut:**
- Cmd+Shift+C (in addition to button click)
- Standard Cmd+C also works when right pane is focused

**Visual Design:**
- Accent button: Orange (#E68A2E) background, white text
- Hover: Slightly darker orange
- Disabled: Muted sand color (#D4AE80)

---

#### FR-6: Status Indicator

**Displays:**
- **Ready:** Green dot • "Ready"
- **Processing:** Animated spinner ⟳ "Analyzing..." (orange color)
- **Error:** Red dot • "Error - see message above"
- **Success:** Green checkmark ✓ "Analysis complete" (fades after 3 seconds)

**Position:** Bottom right corner of window, small subtle text

---

#### FR-7: Warning Banner

**Content:**
```
⚠️ Manual edits are not tracked. Review carefully before sharing.
```

**Behavior:**
- Always visible at bottom of window
- Cannot be dismissed (permanent reminder)
- Links to no action (informational only)

**Visual Design:**
- Background: Light sand (#E8D4BC)
- Text: Charcoal (#2E2E2E)
- Icon: Orange warning triangle

---

### 3.4 Entity Detection & Replacement Logic

#### Entity Type Definitions

**1. Person - Client/Patient**
- **Detects:** First names, full names, nicknames of clients/patients
- **Examples:** "Jane", "Jane Smith", "Aroha Te Whare", "J.S."
- **Replacement:** [CLIENT_A], [CLIENT_B], [CLIENT_C]...
- **Context clues:** Mentioned as "client", "patient", or subject of session

**2. Person - Healthcare Provider**
- **Detects:** Names of practitioners, doctors, therapists
- **Examples:** "Dr. Wilson", "Sarah (psychologist)", "the GP"
- **Replacement:** [PROVIDER_A], [PROVIDER_B]...
- **Context clues:** Professional titles (Dr., therapist), provider roles

**3. Location**
- **Detects:** Addresses, streets, suburbs, cities, landmarks
- **Examples:** "123 Queen Street", "Hamilton", "Middlemore Hospital", "the marae"
- **Replacement:** [LOCATION_A], [LOCATION_B]...
- **Preserves:** General descriptors like "rural area", "urban clinic", "workplace"

**4. Organization**
- **Detects:** Schools, employers, hospitals, government agencies
- **Examples:** "Kāinga Ora", "Auckland Hospital", "XYZ Primary School"
- **Replacement:** [ORGANIZATION_A], [ORGANIZATION_B]...
- **Preserves:** Generic terms like "their employer", "local DHB"

**5. Date**
- **Detects:** Specific dates, birthdates, appointment dates
- **Examples:** "15 March 2024", "born 1985", "next Tuesday"
- **Replacement:** [DATE_A], [DATE_B]...
- **Preserves:** Relative timeframes like "early 2024", "about 6 months ago", "recently"

**6. Identifier**
- **Detects:** NHI numbers, phone numbers, emails, license plates
- **Examples:** "ABC1234", "021-555-1234", "jane@email.com"
- **Replacement:** [ID_A], [ID_B]...

---

#### Contextual Preservation Rules

**What to KEEP (not anonymize):**
- Age: "34-year-old female" → stays unchanged
- Gender: "male client", "she", "they" → stays unchanged
- General diagnoses: "depression", "anxiety disorder" → stays unchanged
- Symptoms: "low mood", "panic attacks" → stays unchanged
- General timeframes: "over the past month", "for two years" → stays unchanged
- Clinical concepts: "CBT intervention", "EMDR session" → stays unchanged
- Relative relationships: "their partner", "the client's child" → stays unchanged
- General locations: "at home", "in their workplace" → stays unchanged

**What to ANONYMIZE:**
- Specific names of people
- Specific addresses or identifiable locations
- Specific organizations or employers
- Exact dates or ages that could identify individuals
- Any unique identifiers (numbers, emails, etc.)

---

### 3.5 Session Memory & Consistency

#### Entity Mapping Persistence

**Within a Session:**
```swift
// Example internal state
[
  "Jane Smith": "CLIENT_A",
  "Aroha": "CLIENT_B", 
  "Dr. Wilson": "PROVIDER_A",
  "Hamilton": "LOCATION_A",
  "15 March 2024": "DATE_A"
]
```

**Behavior:**
1. First detection of "Jane Smith" → assigned CLIENT_A
2. Second mention of "Jane Smith" → looks up mapping, returns CLIENT_A
3. Mention of just "Jane" → LLM infers same person, also CLIENT_A
4. "Clear All" button → mapping dictionary reset
5. App closes → mapping lost (not persisted)

**Edge Cases:**
- **Multiple clients in one note:** "Jane and Tom attended together" → CLIENT_A and CLIENT_B
- **Ambiguous names:** "Chris" could be client or provider → LLM uses context
- **Same name, different people:** LLM should distinguish via context, but may need manual correction

---

### 3.6 Non-Functional Requirements

#### Performance
- Analysis time: Target <10 seconds for typical note (500-1000 words)
- UI remains responsive during processing (async operations)
- Memory usage: <2GB for typical operation
- No memory leaks (verified in testing)

#### Accessibility
- WCAG 2.1 AA compliant (minimum)
- VoiceOver compatible (screen reader support)
- Keyboard navigation: All functions accessible via keyboard
- Color contrast: Minimum 4.5:1 for text
- Resizable text: Supports system text size preferences

#### Reliability
- Graceful degradation if Ollama stops during operation
- Auto-recovery: Attempts to reconnect to Ollama if connection lost
- Data integrity: Original text never modified, always separate from anonymized version
- Error messages: Clear, actionable, user-friendly (never technical jargon)

---

## 4. Technical Architecture

### 4.1 System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SwiftUI Application                         │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                      ContentView.swift                       │  │
│  │                   (Main UI - Two Panes)                      │  │
│  │                                                              │  │
│  │  ┌──────────────────┐              ┌──────────────────┐    │  │
│  │  │ OriginalTextView │              │ AnonymizedTextView│   │  │
│  │  │  (TextEditor)    │              │  (TextEditor)     │   │  │
│  │  │  - Highlighting  │              │  - Highlighting   │   │  │
│  │  │  - Read-only     │              │  - Editable       │   │  │
│  │  └──────────────────┘              └──────────────────┘    │  │
│  │                                                              │  │
│  │  [Analyze Button] [Clear Button] [Copy Button]              │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                ↓                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                       AppViewModel                           │  │
│  │                   (@ObservableObject)                        │  │
│  │                                                              │  │
│  │  @Published var originalText: String                        │  │
│  │  @Published var anonymizedText: String                      │  │
│  │  @Published var isProcessing: Bool                          │  │
│  │  @Published var errorMessage: String?                       │  │
│  │                                                              │  │
│  │  func analyze()                                             │  │
│  │  func clearAll()                                            │  │
│  │  func copyToClipboard()                                     │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                ↓                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                  AnonymizationEngine.swift                   │  │
│  │                    (Business Logic Layer)                    │  │
│  │                                                              │  │
│  │  func anonymizeText(_ text: String) async throws            │  │
│  │    → AnalysisResult                                         │  │
│  │                                                              │  │
│  │  - Orchestrates LLM call                                    │  │
│  │  - Parses response                                          │  │
│  │  - Builds entity map                                        │  │
│  │  - Applies highlighting                                     │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                    ↓                           ↓                   │
│  ┌──────────────────────────┐   ┌──────────────────────────────┐  │
│  │  OllamaService.swift     │   │  EntityMapper.swift          │  │
│  │  (HTTP Communication)    │   │  (Consistency Logic)         │  │
│  │                          │   │                              │  │
│  │  - POST to localhost     │   │  - Tracks mappings           │  │
│  │  - Parse JSON response   │   │  - Ensures consistency       │  │
│  │  - Error handling        │   │  - Reset capability          │  │
│  └──────────────────────────┘   └──────────────────────────────┘  │
│                    ↓                                               │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                    HighlightHelper.swift                     │  │
│  │                    (Text Processing)                         │  │
│  │                                                              │  │
│  │  - NSAttributedString creation                              │  │
│  │  - Yellow highlighting application                          │  │
│  │  - Range calculations                                       │  │
│  └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                ↓
                ┌───────────────────────────────┐
                │    Ollama (External Process)  │
                │    Running on localhost:11434 │
                │                               │
                │    Llama 3.1 8B Model         │
                │    (Downloaded separately)    │
                └───────────────────────────────┘
```

---

### 4.2 Technology Stack

**Primary Language:** Swift 5.9+  
**UI Framework:** SwiftUI (native macOS)  
**Minimum OS:** macOS 12 (Monterey) or later  
**Target Architecture:** Apple Silicon (M-series native), Intel compatible  
**Dependencies:** None (pure Swift/SwiftUI, native URLSession for HTTP)

**External Requirements:**
- Ollama (installed separately via Homebrew)
- Llama 3.1 8B model (downloaded via Ollama)

---

### 4.3 Data Models

#### Entity.swift
```swift
import Foundation

struct Entity: Identifiable, Codable {
    let id: UUID
    let original: String           // e.g., "Jane Smith"
    let replacement: String        // e.g., "CLIENT_A"
    let type: EntityType
    let ranges: [NSRange]          // All occurrences in text
    
    init(original: String, replacement: String, type: EntityType, ranges: [NSRange]) {
        self.id = UUID()
        self.original = original
        self.replacement = replacement
        self.type = type
        self.ranges = ranges
    }
}
```

#### EntityType.swift
```swift
enum EntityType: String, Codable, CaseIterable {
    case person_client = "person_client"
    case person_provider = "person_provider"
    case location = "location"
    case organization = "organization"
    case date = "date"
    case identifier = "identifier"
    
    var displayName: String {
        switch self {
        case .person_client: return "Client"
        case .person_provider: return "Provider"
        case .location: return "Location"
        case .organization: return "Organization"
        case .date: return "Date"
        case .identifier: return "Identifier"
        }
    }
    
    var prefix: String {
        switch self {
        case .person_client: return "CLIENT_"
        case .person_provider: return "PROVIDER_"
        case .location: return "LOCATION_"
        case .organization: return "ORGANIZATION_"
        case .date: return "DATE_"
        case .identifier: return "ID_"
        }
    }
}
```

#### AnalysisResult.swift
```swift
struct AnalysisResult {
    let originalText: String
    let anonymizedText: String
    let entities: [Entity]
    let mapping: [String: String]    // Quick lookup: "Jane Smith" → "CLIENT_A"
    let processingTime: TimeInterval
    
    var entityCount: Int {
        entities.count
    }
    
    var replacementCount: Int {
        entities.reduce(0) { $0 + $1.ranges.count }
    }
}
```

#### OllamaRequest.swift
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

#### OllamaResponse.swift
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
        let positions: [[Int]]    // Array of [start, end] pairs
    }
}
```

---

### 4.4 Architecture Patterns

#### MVVM (Model-View-ViewModel)

**Models** (`Models/`)
- Pure data structures
- No business logic
- Codable for JSON parsing
- Equatable where needed

**Views** (`Views/`)
- SwiftUI views only
- No business logic
- Binds to ViewModel via @ObservedObject or @StateObject
- Handles user interaction, delegates to ViewModel

**ViewModels** (`ViewModels/`)
- @ObservableObject classes
- @Published properties for reactive UI updates
- Contains all business logic
- Coordinates between Services
- Handles state management

**Services** (`Services/`)
- Single-responsibility classes
- No UI dependencies
- Pure business logic
- Network calls, data processing, etc.

**Utilities** (`Utilities/`)
- Helper functions and extensions
- Reusable across the app
- No state

---

#### Dependency Injection Pattern

```swift
// Good: Testable and flexible
class AppViewModel: ObservableObject {
    private let ollamaService: OllamaServiceProtocol
    private let entityMapper: EntityMapperProtocol
    
    init(
        ollamaService: OllamaServiceProtocol = OllamaService(),
        entityMapper: EntityMapperProtocol = EntityMapper()
    ) {
        self.ollamaService = ollamaService
        self.entityMapper = entityMapper
    }
}

// Enables testing with mock services
let viewModel = AppViewModel(
    ollamaService: MockOllamaService(),
    entityMapper: MockEntityMapper()
)
```

---

#### Protocol-Oriented Design

```swift
protocol OllamaServiceProtocol {
    func sendRequest(text: String, systemPrompt: String) async throws -> String
    func checkConnection() async throws -> Bool
}

protocol EntityMapperProtocol {
    func getCode(for entity: String, type: EntityType) -> String
    func reset()
    var currentMappings: [String: String] { get }
}
```

---

### 4.5 Thread Safety & Concurrency

#### Main Actor Usage

```swift
@MainActor
class AppViewModel: ObservableObject {
    @Published var originalText: String = ""
    @Published var anonymizedText: String = ""
    @Published var isProcessing: Bool = false
    
    // All UI updates happen on main thread automatically
    func analyze() async {
        isProcessing = true
        
        do {
            // Heavy work done off main thread by OllamaService
            let result = try await engine.anonymizeText(originalText)
            
            // UI updates automatically on main thread because of @MainActor
            anonymizedText = result.anonymizedText
            applyHighlights(result)
        } catch {
            handleError(error)
        }
        
        isProcessing = false
    }
}
```

#### Async/Await for Network Operations

```swift
class OllamaService: OllamaServiceProtocol {
    func sendRequest(text: String, systemPrompt: String) async throws -> String {
        let request = buildRequest(text: text, systemPrompt: systemPrompt)
        
        // URLSession automatically handles threading
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AppError.networkError(NSError(domain: "OllamaService", code: -1))
        }
        
        let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return ollamaResponse.response
    }
}
```

---

## 5. Ollama Integration Strategy

### 5.1 Why Ollama is NOT Bundled

**Reasons Against Bundling:**
1. **Size:** Ollama binary (~200MB) + Llama 3.1 8B model (~4.7GB) = 4.9GB app bundle
2. **Updates:** Ollama and models update frequently; bundling locks to a version
3. **Permissions:** Bundled binaries require special macOS code signing and notarization
4. **User flexibility:** Users may already have Ollama installed; bundling duplicates
5. **Distribution:** App Store limits app size; 5GB bundle would exceed guidelines
6. **Maintenance:** Separate installation allows independent updates and troubleshooting

**Better Approach:** Detect, guide install, automate where possible

---

### 5.2 Setup & Installation Flow

#### Stage 1: First Launch Detection

```
App Launches
    ↓
┌─────────────────────────────────────┐
│ SetupManager.checkSetup()          │
│   - Check: which ollama             │
│   - Check: curl localhost:11434     │
│   - Check: ollama list | grep llama │
└─────────────────────────────────────┘
    ↓
┌─────────────────┬─────────────────┬──────────────────┐
│ Case 1:         │ Case 2:         │ Case 3:          │
│ All Ready ✓     │ Ollama Missing  │ Model Missing    │
│ → Main App      │ → Setup Screen  │ → Download Screen│
└─────────────────┴─────────────────┴──────────────────┘
```

---

#### Stage 2: Setup Screen (If Ollama Not Installed)

**UI Design:**

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│              🚀 Welcome to ClinicalAnon            │
│                                                     │
│  First-time setup: Ollama is required to run       │
│  this application locally and privately.           │
│                                                     │
│  ┌───────────────────────────────────────────┐    │
│  │  ✅ OPTION 1: Automatic Install           │    │
│  │                                            │    │
│  │  We'll install Ollama using Homebrew.     │    │
│  │  This requires admin password.            │    │
│  │                                            │    │
│  │  [Install Ollama Automatically]           │    │
│  │                                            │    │
│  └───────────────────────────────────────────┘    │
│                                                     │
│  ┌───────────────────────────────────────────┐    │
│  │  📖 OPTION 2: Manual Install              │    │
│  │                                            │    │
│  │  1. Open Terminal                         │    │
│  │  2. Paste: brew install ollama            │    │
│  │  3. Press Enter and wait for completion   │    │
│  │  4. Click "Check Again" below             │    │
│  │                                            │    │
│  │  [Copy Command]  [Check Again]            │    │
│  │                                            │    │
│  └───────────────────────────────────────────┘    │
│                                                     │
│  Not sure? [Read Full Setup Guide]                │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Brand Colors Applied:**
- Header: Teal (#0A6B7C)
- Cards: Warm White background (#FAF7F4)
- Primary Button: Teal with white text
- Secondary Button: Outlined with Charcoal border
- Icons: Orange (#E68A2E) for energy/action items

---

#### Stage 3: Model Download Screen (If Ollama Present, Model Missing)

**UI Design:**

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│              📦 Download AI Model                  │
│                                                     │
│  One-time setup: Download the Llama 3.1 model     │
│  (~4.7 GB). This will be stored locally and       │
│  work completely offline afterwards.               │
│                                                     │
│  ┌───────────────────────────────────────────┐    │
│  │                                            │    │
│  │  [Start Download]                         │    │
│  │                                            │    │
│  │  ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░  45%              │    │
│  │                                            │    │
│  │  2.1 GB of 4.7 GB                         │    │
│  │  Speed: 15 MB/s                           │    │
│  │  Time remaining: ~3 minutes               │    │
│  │                                            │    │
│  │  [Cancel]                                 │    │
│  │                                            │    │
│  └───────────────────────────────────────────┘    │
│                                                     │
│  💡 Tip: This download happens once. The model    │
│     stays on your Mac and never contacts the      │
│     internet again.                                │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Progress Tracking:**
- Real-time updates from `ollama pull` command
- Percentage completion
- Data transferred / Total size
- Estimated time remaining
- Cancel option (stops download, can resume later)

---

### 5.3 What the App CAN Automate

#### ✅ 1. Detect Ollama Installation

```bash
which ollama
# Returns: /opt/homebrew/bin/ollama (if installed)
# Returns: (empty) if not installed
```

**Swift Implementation:**
```swift
func isOllamaInstalled() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["ollama"]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    
    do {
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return !(output?.isEmpty ?? true) && process.terminationStatus == 0
    } catch {
        return false
    }
}
```

---

#### ✅ 2. Check Ollama Service Status

```bash
curl -s http://localhost:11434/api/tags
# Returns JSON list of models if running
# Returns connection error if not running
```

**Swift Implementation:**
```swift
func isOllamaRunning() async -> Bool {
    guard let url = URL(string: "http://localhost:11434/api/tags") else {
        return false
    }
    
    do {
        let (_, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse {
            return httpResponse.statusCode == 200
        }
        return false
    } catch {
        return false
    }
}
```

---

#### ✅ 3. Start Ollama Service

```bash
ollama serve &
# Starts Ollama in background
```

**Swift Implementation:**
```swift
func startOllama() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ollama")
    process.arguments = ["serve"]
    
    // Run in background
    try process.run()
    
    // Don't wait for it to finish (it runs as daemon)
}
```

**Note:** App should attempt to start Ollama automatically if installed but not running.

---

#### ✅ 4. Check if Model Downloaded

```bash
ollama list | grep "llama3.1:8b"
# Returns model info if present
# Returns empty if not downloaded
```

**Swift Implementation:**
```swift
func isModelDownloaded(modelName: String = "llama3.1:8b") -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ollama")
    process.arguments = ["list"]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    
    do {
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return output.contains(modelName)
    } catch {
        return false
    }
}
```

---

#### ✅ 5. Trigger Model Download with Progress

```bash
ollama pull llama3.1:8b
# Downloads model with progress output
```

**Swift Implementation:**
```swift
func downloadModel(modelName: String = "llama3.1:8b", 
                   progressHandler: @escaping (Double, String) -> Void) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ollama")
    process.arguments = ["pull", modelName]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    
    // Monitor output for progress
    pipe.fileHandleForReading.readabilityHandler = { fileHandle in
        let data = fileHandle.availableData
        if let output = String(data: data, encoding: .utf8) {
            // Parse progress from output
            // Format: "pulling manifest... 25%"
            if let progress = parseProgress(from: output) {
                DispatchQueue.main.async {
                    progressHandler(progress, output)
                }
            }
        }
    }
    
    try process.run()
    process.waitUntilExit()
    
    if process.terminationStatus != 0 {
        throw AppError.modelDownloadFailed
    }
}

private func parseProgress(from output: String) -> Double? {
    // Parse percentage from Ollama output
    // Example: "pulling manifest... 45%"
    let pattern = #"(\d+)%"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
          let range = Range(match.range(at: 1), in: output),
          let percentage = Double(output[range]) else {
        return nil
    }
    return percentage / 100.0
}
```

---

### 5.4 What the App CANNOT Fully Automate

#### ❌ 1. Install Homebrew

**Limitation:** Homebrew installation requires Terminal interaction and password input.

**What App CAN Do:**
- Detect if Homebrew is installed: `which brew`
- Provide copy-paste command: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- Open Terminal with command pre-filled (if user clicks button)

**User Must:**
- Review Homebrew install script
- Enter admin password in Terminal
- Wait for installation to complete

---

#### ❌ 2. Install Ollama via Homebrew (without Terminal)

**Limitation:** `brew install` requires Terminal interaction for password.

**What App CAN Do:**
- Provide command: `brew install ollama`
- Copy to clipboard with one click
- Open Terminal app automatically
- Poll to detect when installation completes

**What App CANNOT Do:**
- Execute `brew install` silently (requires admin privileges)
- Input password on user's behalf (security restriction)

**Workaround for "Automatic" Install:**
```swift
func attemptAutomaticInstall() {
    // Opens Terminal and pre-fills the command
    let script = """
    tell application "Terminal"
        activate
        do script "echo 'ClinicalAnon is installing Ollama...' && brew install ollama"
    end tell
    """
    
    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        
        if let error = error {
            print("AppleScript error: \(error)")
        }
    }
    
    // Then poll to detect completion
    startPollingForOllamaInstallation()
}
```

**User Experience:**
1. User clicks "Install Automatically"
2. Terminal opens with command ready
3. User enters password and presses Enter
4. App detects completion and moves to next step

---

### 5.5 SetupManager Implementation

**File:** `Utilities/SetupManager.swift`

```swift
import Foundation
import Combine

enum SetupState: Equatable {
    case checking
    case ready
    case needsHomebrew
    case needsOllama
    case needsModel
    case downloadingModel(progress: Double)
    case startingOllama
    case error(String)
}

@MainActor
class SetupManager: ObservableObject {
    @Published var state: SetupState = .checking
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: String = ""
    
    private var pollTimer: Timer?
    
    // MARK: - Initial Setup Check
    
    func checkSetup() async {
        state = .checking
        
        // Check Homebrew
        guard isHomebrewInstalled() else {
            state = .needsHomebrew
            return
        }
        
        // Check Ollama
        guard isOllamaInstalled() else {
            state = .needsOllama
            return
        }
        
        // Check if running
        let running = await isOllamaRunning()
        if !running {
            do {
                try startOllama()
                try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
            } catch {
                state = .error("Failed to start Ollama: \(error.localizedDescription)")
                return
            }
        }
        
        // Check model
        guard isModelDownloaded() else {
            state = .needsModel
            return
        }
        
        state = .ready
    }
    
    // MARK: - Homebrew
    
    func isHomebrewInstalled() -> Bool {
        return executeCommand("/bin/bash", args: ["-c", "which brew"]) != nil
    }
    
    // MARK: - Ollama Installation
    
    func isOllamaInstalled() -> Bool {
        return executeCommand("/usr/bin/which", args: ["ollama"]) != nil
    }
    
    func installOllama() async throws {
        // Opens Terminal with pre-filled command
        let script = """
        tell application "Terminal"
            activate
            do script "brew install ollama && echo 'INSTALLATION_COMPLETE'"
        end tell
        """
        
        guard let appleScript = NSAppleScript(source: script) else {
            throw AppError.ollamaInstallFailed
        }
        
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        
        if let error = error {
            throw AppError.ollamaInstallFailed
        }
        
        // Poll for completion
        startPollingForInstallation()
    }
    
    private func startPollingForInstallation() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.isOllamaInstalled() == true {
                    self?.pollTimer?.invalidate()
                    await self?.checkSetup()
                }
            }
        }
    }
    
    // MARK: - Ollama Service
    
    func isOllamaRunning() async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/tags") else {
            return false
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }
    
    func startOllama() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ollama")
        process.arguments = ["serve"]
        
        // Launch in background
        try process.run()
        
        state = .startingOllama
    }
    
    // MARK: - Model Download
    
    func isModelDownloaded(modelName: String = "llama3.1:8b") -> Bool {
        guard let output = executeCommand("/opt/homebrew/bin/ollama", args: ["list"]) else {
            return false
        }
        return output.contains(modelName)
    }
    
    func downloadModel(modelName: String = "llama3.1:8b") async throws {
        state = .downloadingModel(progress: 0.0)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ollama")
        process.arguments = ["pull", modelName]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        // Monitor progress
        Task {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                await MainActor.run {
                    self.downloadStatus = line
                    
                    // Parse progress
                    if let progress = parseProgress(from: line) {
                        self.downloadProgress = progress
                        self.state = .downloadingModel(progress: progress)
                    }
                }
            }
        }
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            await checkSetup() // Re-check to confirm ready
        } else {
            throw AppError.modelDownloadFailed
        }
    }
    
    // MARK: - Helpers
    
    private func executeCommand(_ command: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    
    private func parseProgress(from line: String) -> Double? {
        // Ollama output format: "pulling 8a29a5e6..."
        // Or: "pulling manifest... 45%"
        let pattern = #"(\d+)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let percentage = Double(line[range]) else {
            return nil
        }
        return percentage / 100.0
    }
}
```

---

### 5.6 Setup UI Views

#### SetupView.swift

```swift
import SwiftUI

struct SetupView: View {
    @StateObject private var setupManager = SetupManager()
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            switch setupManager.state {
            case .checking:
                checkingView
                
            case .ready:
                readyView
                
            case .needsHomebrew:
                needsHomebrewView
                
            case .needsOllama:
                needsOllamaView
                
            case .needsModel:
                needsModelView
                
            case .downloadingModel(let progress):
                downloadingView(progress: progress)
                
            case .startingOllama:
                startingView
                
            case .error(let message):
                errorView(message: message)
            }
        }
        .frame(maxWidth: 600)
        .padding(DesignSystem.Spacing.xlarge)
        .task {
            await setupManager.checkSetup()
        }
    }
    
    // MARK: - Subviews
    
    private var checkingView: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Checking setup...")
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.primaryTeal)
        }
    }
    
    private var needsOllamaView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
            // Header
            VStack(spacing: DesignSystem.Spacing.small) {
                Text("🚀")
                    .font(.system(size: 48))
                
                Text("Welcome to ClinicalAnon")
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                
                Text("First-time setup: Ollama is required to run this application locally and privately.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.charcoal)
                    .multilineTextAlignment(.center)
            }
            
            // Option 1: Automatic
            SetupCard(title: "✅ OPTION 1: Automatic Install") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Text("We'll install Ollama using Homebrew. This requires admin password.")
                        .font(DesignSystem.Typography.body)
                    
                    Button("Install Ollama Automatically") {
                        Task {
                            try? await setupManager.installOllama()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            
            // Option 2: Manual
            SetupCard(title: "📖 OPTION 2: Manual Install") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Text("1. Open Terminal")
                    Text("2. Paste: brew install ollama")
                        .font(DesignSystem.Typography.mono)
                    Text("3. Press Enter and wait for completion")
                    Text("4. Click 'Check Again' below")
                    
                    HStack {
                        Button("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("brew install ollama", forType: .string)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        
                        Button("Check Again") {
                            Task {
                                await setupManager.checkSetup()
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            
            Button("Read Full Setup Guide") {
                if let url = URL(string: "https://ollama.ai/download") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(LinkButtonStyle())
        }
    }
    
    private var needsModelView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
            VStack(spacing: DesignSystem.Spacing.small) {
                Text("📦")
                    .font(.system(size: 48))
                
                Text("Download AI Model")
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                
                Text("One-time setup: Download the Llama 3.1 model (~4.7 GB). This will be stored locally and work completely offline afterwards.")
                    .font(DesignSystem.Typography.body)
                    .multilineTextAlignment(.center)
            }
            
            SetupCard(title: "") {
                VStack(spacing: DesignSystem.Spacing.medium) {
                    Button("Start Download") {
                        Task {
                            try? await setupManager.downloadModel()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    
                    Text("💡 Tip: This download happens once. The model stays on your Mac and never contacts the internet again.")
                        .font(DesignSystem.Typography.small)
                        .foregroundColor(DesignSystem.Colors.charcoal)
                        .padding(DesignSystem.Spacing.medium)
                        .background(DesignSystem.Colors.warmWhite)
                        .cornerRadius(DesignSystem.Layout.cornerRadius)
                }
            }
        }
    }
    
    private func downloadingView(progress: Double) -> some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Text("📦 Downloading Model")
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.primaryTeal)
            
            SetupCard(title: "") {
                VStack(spacing: DesignSystem.Spacing.medium) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: DesignSystem.Colors.accentOrange))
                    
                    Text("\(Int(progress * 100))%")
                        .font(DesignSystem.Typography.title)
                        .foregroundColor(DesignSystem.Colors.charcoal)
                    
                    if !setupManager.downloadStatus.isEmpty {
                        Text(setupManager.downloadStatus)
                            .font(DesignSystem.Typography.small)
                            .foregroundColor(DesignSystem.Colors.charcoal)
                    }
                }
            }
        }
    }
    
    private var readyView: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Text("✅")
                .font(.system(size: 64))
            
            Text("Setup Complete!")
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.primaryTeal)
            
            Text("ClinicalAnon is ready to use")
                .font(DesignSystem.Typography.body)
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Text("⚠️")
                .font(.system(size: 64))
            
            Text("Setup Error")
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.errorRed)
            
            Text(message)
                .font(DesignSystem.Typography.body)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task {
                    await setupManager.checkSetup()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
    
    private var startingView: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Starting Ollama service...")
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.primaryTeal)
        }
    }
}

// MARK: - Supporting Views

struct SetupCard<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            if !title.isEmpty {
                Text(title)
                    .font(DesignSystem.Typography.subtitle)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)
            }
            
            content
        }
        .padding(DesignSystem.Spacing.large)
        .background(DesignSystem.Colors.warmWhite)
        .cornerRadius(DesignSystem.Layout.cornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}
```

---

### 5.7 App Launch Logic

#### ClinicalAnonApp.swift

```swift
import SwiftUI

@main
struct ClinicalAnonApp: App {
    @StateObject private var setupManager = SetupManager()
    @AppStorage("setupCompleted") private var setupCompleted = false
    
    var body: some Scene {
        WindowGroup {
            Group {
                if setupCompleted && setupManager.state == .ready {
                    ContentView()
                } else {
                    SetupView()
                        .onReceive(setupManager.$state) { state in
                            if state == .ready {
                                setupCompleted = true
                            }
                        }
                }
            }
            .frame(minWidth: DesignSystem.Layout.windowMinWidth,
                   minHeight: DesignSystem.Layout.windowMinHeight)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
```

**Key Behavior:**
- On first launch: Shows SetupView
- After setup complete: Sets `setupCompleted = true` in UserDefaults
- On subsequent launches: Quickly checks setup, then proceeds to main app
- If setup broken (Ollama uninstalled): Returns to SetupView

---

## 6. LLM Prompt Engineering

### 6.1 System Prompt (Constant)

This prompt is sent with every anonymization request to establish context and rules.

```
You are a clinical text anonymization system for healthcare practitioners in Aotearoa New Zealand. Your task is to identify and replace all personally identifying information while preserving clinical context and therapeutic meaning.

ENTITY TYPES AND REPLACEMENT RULES:

1. PERSON - CLIENT/PATIENT
   Replace with: [CLIENT_A], [CLIENT_B], [CLIENT_C], etc.
   Examples: "Jane Smith", "Aroha", "J.S.", "the client", "her daughter Emma"
   Context: Clients, patients, family members mentioned in clinical context

2. PERSON - HEALTHCARE PROVIDER
   Replace with: [PROVIDER_A], [PROVIDER_B], etc.
   Examples: "Dr. Wilson", "Sarah (psychologist)", "the GP", "their therapist"
   Context: Healthcare professionals, practitioners

3. LOCATION
   Replace with: [LOCATION_A], [LOCATION_B], etc.
   Examples: "123 Queen Street", "Hamilton", "Middlemore Hospital", "the marae in Rotorua"
   Preserve: General descriptors like "rural area", "urban clinic", "at home", "workplace"

4. ORGANIZATION
   Replace with: [ORGANIZATION_A], [ORGANIZATION_B], etc.
   Examples: "Kāinga Ora", "Auckland Hospital", "ABC Primary School", "Microsoft"
   Preserve: Generic terms like "their employer", "local DHB", "a tech company"

5. DATE
   Replace with: [DATE_A], [DATE_B], etc.
   Examples: "15 March 2024", "born in 1985", "next Tuesday"
   Preserve: Relative timeframes like "early 2024", "about 6 months ago", "recently", "for two years"

6. IDENTIFIER
   Replace with: [ID_A], [ID_B], etc.
   Examples: NHI numbers, phone numbers, email addresses, license plates
   Examples: "ABC1234", "021-555-1234", "jane@email.com"

CRITICAL RULES:

1. CONSISTENCY: Same entity must always get the same code throughout the text.
   Example: If "Jane Smith" becomes [CLIENT_A] once, it must always be [CLIENT_A]

2. CONTEXT AWARENESS: Use surrounding text to disambiguate.
   - "Dawn woke at dawn" → "[CLIENT_A] woke at dawn" (name vs. time of day)
   - "Chris is a psychologist" vs "Chris attended therapy" → PROVIDER vs CLIENT

3. PRESERVE CLINICAL INFORMATION:
   Keep: Age, gender, diagnosis names, symptoms, treatment approaches, relative timeframes, general locations
   Examples to PRESERVE:
   - "34-year-old female"
   - "diagnosed with major depressive disorder"
   - "experiencing panic attacks"
   - "using CBT techniques"
   - "over the past three months"
   - "at their workplace"

4. TE REO MĀORI COMPETENCE:
   Treat Māori names with same care as English names.
   Examples: "Aroha Te Whare", "Kahu", "Wiremu"
   Handle macrons correctly: "Māori" not "Maori"

5. PARTIAL MENTIONS:
   If "Jane Smith" appears first, then just "Jane" later, both should become [CLIENT_A]

6. FAMILY RELATIONSHIPS:
   "Jane's daughter Emma" → "[CLIENT_A]'s daughter [CLIENT_B]"
   Preserve relationship, anonymize names

OUTPUT FORMAT (strict JSON only):
{
  "anonymized_text": "Full text with replacements applied",
  "entities": [
    {
      "original": "exact text found in original",
      "replacement": "code used (e.g., CLIENT_A)",
      "type": "person_client|person_provider|location|organization|date|identifier",
      "positions": [[start_index, end_index], [start_index, end_index]]
    }
  ]
}

CRITICAL: Return ONLY valid JSON. No explanation, no markdown formatting, no code blocks. Just the JSON object.
```

---

### 6.2 User Prompt Template

For each anonymization request, combine the system prompt with the user's text:

```swift
func constructPrompt(userText: String) -> String {
    return """
    Anonymize the following clinical note according to the rules above:
    
    --- BEGIN CLINICAL NOTE ---
    \(userText)
    --- END CLINICAL NOTE ---
    
    Remember: 
    - Same entity = same replacement code throughout
    - Preserve clinical context and information
    - Handle te reo Māori names appropriately
    - Return only JSON, no other text
    """
}
```

---

### 6.3 Prompt Validation & Testing

#### Test Cases for Prompt Quality

**Test 1: Basic Name Consistency**
```
Input: "Jane Smith came to the clinic. Dr. Wilson saw Jane for 50 minutes."

Expected Output:
{
  "anonymized_text": "[CLIENT_A] came to the clinic. [PROVIDER_A] saw [CLIENT_A] for 50 minutes.",
  "entities": [
    {"original": "Jane Smith", "replacement": "CLIENT_A", "type": "person_client", ...},
    {"original": "Jane", "replacement": "CLIENT_A", "type": "person_client", ...},
    {"original": "Dr. Wilson", "replacement": "PROVIDER_A", "type": "person_provider", ...}
  ]
}

Validation:
✓ "Jane Smith" and "Jane" both map to CLIENT_A (consistency)
✓ Provider identified correctly
✓ Clinical detail preserved ("50 minutes")
```

---

**Test 2: Māori Names**
```
Input: "Aroha Te Whare discussed whakamā with her therapist Kahu at the Te Arawa marae."

Expected Output:
{
  "anonymized_text": "[CLIENT_A] discussed whakamā with her therapist [PROVIDER_A] at the [LOCATION_A].",
  ...
}

Validation:
✓ Māori names detected and anonymized
✓ "whakamā" (concept) preserved - not a name
✓ "Te Arawa marae" identified as location
```

---

**Test 3: Context Disambiguation**
```
Input: "Dawn woke at dawn feeling anxious."

Expected Output:
{
  "anonymized_text": "[CLIENT_A] woke at dawn feeling anxious.",
  ...
}

Validation:
✓ First "Dawn" is name → CLIENT_A
✓ Second "dawn" is time of day → preserved
✓ Emotional state preserved
```

---

**Test 4: Dates & Timeframes**
```
Input: "Client born 15 March 1985. Symptoms started in early 2024, approximately 6 months ago."

Expected Output:
{
  "anonymized_text": "Client born [DATE_A]. Symptoms started in early 2024, approximately 6 months ago.",
  ...
}

Validation:
✓ Specific date anonymized
✓ General timeframe "early 2024" preserved
✓ Relative time "6 months ago" preserved
```

---

**Test 5: Locations - Specific vs. General**
```
Input: "Lives at 123 Queen St, Hamilton. Works in an office in the CBD. Grew up in a rural area."

Expected Output:
{
  "anonymized_text": "Lives at [LOCATION_A], [LOCATION_B]. Works in an office in the CBD. Grew up in a rural area.",
  ...
}

Validation:
✓ Specific address anonymized
✓ City anonymized
✓ "CBD" and "rural area" preserved (general)
```

---

**Test 6: Organizations**
```
Input: "Works for Microsoft. Referred by Kāinga Ora. Seeing a counselor at their employer's EAP."

Expected Output:
{
  "anonymized_text": "Works for [ORGANIZATION_A]. Referred by [ORGANIZATION_B]. Seeing a counselor at their employer's EAP.",
  ...
}

Validation:
✓ Specific organizations anonymized
✓ Generic "employer" and "EAP" preserved
```

---

**Test 7: Family Relationships**
```
Input: "Sarah brought her daughter Emma (aged 7) and son Tom (aged 10) to the session."

Expected Output:
{
  "anonymized_text": "[CLIENT_A] brought her daughter [CLIENT_B] (aged 7) and son [CLIENT_C] (aged 10) to the session.",
  ...
}

Validation:
✓ Mother and both children anonymized
✓ Ages preserved (clinical relevance)
✓ Relationship terms preserved
```

---

### 6.4 Response Parsing Strategy

#### Expected JSON Structure from LLM

```json
{
  "anonymized_text": "Full anonymized text here",
  "entities": [
    {
      "original": "Jane Smith",
      "replacement": "CLIENT_A",
      "type": "person_client",
      "positions": [[0, 10], [45, 49]]
    }
  ]
}
```

#### Swift Parsing Implementation

```swift
func parseLLMResponse(_ jsonString: String) throws -> LLMAnonymizationResponse {
    // Remove markdown code blocks if present (LLM sometimes adds despite instructions)
    let cleanedJSON = jsonString
        .replacingOccurrences(of: "```json\n", with: "")
        .replacingOccurrences(of: "```\n", with: "")
        .replacingOccurrences(of: "```", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    
    guard let data = cleanedJSON.data(using: .utf8) else {
        throw AppError.invalidResponse
    }
    
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    
    do {
        let response = try decoder.decode(LLMAnonymizationResponse.self, from: data)
        return response
    } catch {
        print("JSON parsing error: \(error)")
        print("Attempted to parse: \(cleanedJSON)")
        throw AppError.invalidResponse
    }
}
```

---

### 6.5 Prompt Refinement Strategy

#### Iterative Improvement Process

**Phase 1: Initial Testing (Week 1)**
- Test with 20 real clinical notes (manually anonymized first for validation)
- Measure accuracy: % of entities correctly detected
- Identify failure patterns (e.g., always misses certain name types)

**Phase 2: Prompt Adjustments (Week 2)**
- Add specific examples to prompt for common failure cases
- Refine context clues for disambiguation
- Test again with same 20 notes + 20 new ones

**Phase 3: Edge Case Handling (Week 3)**
- Focus on known weak areas:
  - Māori names with macrons
  - Hyphenated names
  - Nicknames vs. real names
  - Professional titles (Dr., Prof., etc.)
- Add explicit instructions for these cases

**Phase 4: User Feedback Loop (Ongoing)**
- Collect real-world failures from practitioners
- Add representative examples to test suite
- Monthly prompt review and refinement

---

## 7. Development Standards

### 7.1 Architecture & Code Organization

#### File Structure

```
ClinicalAnon/
├── ClinicalAnonApp.swift              # App entry point, window config
├── Views/
│   ├── ContentView.swift              # Main two-pane interface
│   ├── SetupView.swift                # First-launch setup wizard
│   ├── Components/
│   │   ├── TextEditorView.swift       # Custom TextEditor with highlighting
│   │   ├── ActionButton.swift         # Reusable button component
│   │   └── StatusIndicator.swift      # Status bar component
├── ViewModels/
│   └── AppViewModel.swift             # Main app state and logic
├── Models/
│   ├── Entity.swift                   # Entity data structure
│   ├── AnalysisResult.swift           # Analysis result structure
│   ├── EntityType.swift               # Entity type enum
│   ├── OllamaRequest.swift            # API request model
│   └── OllamaResponse.swift           # API response models
├── Services/
│   ├── OllamaService.swift            # HTTP communication with Ollama
│   ├── AnonymizationEngine.swift      # Core anonymization logic
│   └── EntityMapper.swift             # Entity tracking and consistency
├── Utilities/
│   ├── DesignSystem.swift             # Centralized design constants
│   ├── AppError.swift                 # Custom error types
│   ├── HighlightHelper.swift          # Text highlighting logic
│   └── SetupManager.swift             # Ollama setup and detection
├── Resources/
│   ├── Info.plist                     # App metadata
│   └── Assets.xcassets/               # Images, colors, icons
└── Tests/
    ├── ClinicalAnonTests/             # Unit tests
    │   ├── OllamaServiceTests.swift
    │   ├── EntityMapperTests.swift
    │   ├── AnonymizationEngineTests.swift
    │   └── HighlightHelperTests.swift
    └── ClinicalAnonUITests/           # UI tests
        └── AppFlowTests.swift
```

---

### 7.2 Naming Conventions

#### General Rules

**Variables & Properties:** camelCase
```swift
// Good
let anonymizedText: String
private var entityMappingCache: [String: String]
@Published var isProcessing: Bool

// Bad
let AnonymizedText: String
var entity_mapping_cache: [String: String]
var processing: Bool
```

**Functions:** camelCase, verb-based
```swift
// Good
func anonymizeText(_ input: String) async throws -> String
func resetEntityMappings()
func checkOllamaStatus() async -> Bool

// Bad
func text(_ input: String) -> String
func reset()
func status() -> Bool
```

**Types (Classes, Structs, Enums):** PascalCase
```swift
// Good
class AnonymizationEngine
struct AnalysisResult
enum EntityType

// Bad
class anonymizationEngine
struct analysisResult
enum entitytype
```

**Constants:** camelCase with descriptive names
```swift
// Good
let defaultTimeout: TimeInterval = 30.0
let maxTextLength: Int = 100_000

// Bad
let TIMEOUT: TimeInterval = 30.0
let max_length: Int = 100_000
```

---

### 7.3 Code Organization Within Files

#### Standard File Structure

```swift
//
//  FileName.swift
//  ClinicalAnon
//
//  Purpose: Brief description of what this file does
//  Dependencies: List key dependencies (if any)
//

import SwiftUI
import Combine // List all imports

// MARK: - Main Type Definition

class ClassName: ObservableObject {
    
    // MARK: - Properties
    
    // Published properties first
    @Published var propertyName: Type
    
    // State properties
    @State private var privateProperty: Type
    
    // Regular properties
    private let service: ServiceType
    private var cache: [String: String] = [:]
    
    // MARK: - Initialization
    
    init(service: ServiceType = DefaultService()) {
        self.service = service
    }
    
    // MARK: - Public Methods
    
    func publicMethod() async {
        // Implementation
    }
    
    // MARK: - Private Methods
    
    private func helperMethod() {
        // Implementation
    }
    
    // MARK: - Computed Properties
    
    var computedProperty: Type {
        // Implementation
    }
}

// MARK: - Extensions

extension ClassName {
    // Related functionality grouped by extension
}

// MARK: - Protocols

protocol ClassNameProtocol {
    // Protocol definition if needed
}

// MARK: - Preview

#Preview {
    ContentView()
}
```

---

### 7.4 Documentation Standards

#### Function Documentation

```swift
/// Anonymizes clinical text by replacing personally identifying information
///
/// This method sends text to the local Ollama LLM, which detects entities according
/// to clinical anonymization rules. The same entity always receives the same replacement
/// code throughout the text for consistency.
///
/// - Parameter text: The original clinical note text to anonymize
/// - Returns: An `AnalysisResult` containing the anonymized text, entity mappings,
///            and metadata about the anonymization process
/// - Throws: `AppError.ollamaNotRunning` if Ollama service is unavailable
///           `AppError.invalidResponse` if LLM returns malformed JSON
///           `AppError.timeout` if request exceeds 30 seconds
///
/// - Important: This method does not modify the original text. The input is preserved
///              in the returned `AnalysisResult.originalText` property.
///
/// Example:
/// ```swift
/// let result = try await anonymize(text: "Jane Smith attended the session.")
/// print(result.anonymizedText) // "[CLIENT_A] attended the session."
/// ```
func anonymizeText(_ text: String) async throws -> AnalysisResult {
    // Implementation
}
```

---

#### Complex Logic Comments

```swift
// Good: Explains WHY, not just WHAT
// We preserve the original character ranges before applying replacements
// because the highlight system needs to map to the original text positions,
// not the anonymized version which has different string lengths
let originalRanges = entities.map { $0.ranges }

// Bad: States the obvious
// Create array of ranges
let originalRanges = entities.map { $0.ranges }
```

---

### 7.5 Error Handling

#### Custom Error Enum

**File:** `Utilities/AppError.swift`

```swift
import Foundation

enum AppError: LocalizedError {
    case ollamaNotInstalled
    case ollamaNotRunning
    case modelNotFound(String)
    case invalidResponse
    case timeout
    case networkError(Error)
    case ollamaInstallFailed
    case modelDownloadFailed
    case parsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .ollamaNotInstalled:
            return "Ollama is not installed on this system."
            
        case .ollamaNotRunning:
            return "Ollama service is not running."
            
        case .modelNotFound(let model):
            return "Model '\(model)' is not installed."
            
        case .invalidResponse:
            return "Received invalid response from Ollama. Please try again."
            
        case .timeout:
            return "Request timed out after 30 seconds."
            
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
            
        case .ollamaInstallFailed:
            return "Failed to install Ollama. Please try manual installation."
            
        case .modelDownloadFailed:
            return "Failed to download model. Check your internet connection."
            
        case .parsingError(let details):
            return "Failed to parse LLM response: \(details)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .ollamaNotInstalled:
            return "Install Ollama by running: brew install ollama"
            
        case .ollamaNotRunning:
            return "Start Ollama by running: ollama serve"
            
        case .modelNotFound(let model):
            return "Download the model by running: ollama pull \(model)"
            
        case .invalidResponse, .parsingError:
            return "This may be a temporary issue. Try again or simplify your text."
            
        case .timeout:
            return "Try with a shorter text, or check if Ollama is responding."
            
        case .networkError:
            return "Check that Ollama is running on localhost:11434"
            
        case .ollamaInstallFailed:
            return "Visit https://ollama.ai for manual installation instructions."
            
        case .modelDownloadFailed:
            return "Check your internet connection and try again."
        }
    }
    
    var failureReason: String? {
        switch self {
        case .ollamaNotInstalled:
            return "The Ollama binary was not found in the system PATH."
            
        case .ollamaNotRunning:
            return "No response received from localhost:11434"
            
        case .modelNotFound:
            return "The specified model is not listed in 'ollama list'"
            
        case .invalidResponse:
            return "LLM returned non-JSON or malformed JSON"
            
        case .timeout:
            return "Request exceeded 30 second limit"
            
        case .networkError(let error):
            return error.localizedDescription
            
        case .ollamaInstallFailed:
            return "Homebrew installation command returned non-zero exit code"
            
        case .modelDownloadFailed:
            return "'ollama pull' command failed"
            
        case .parsingError(let details):
            return details
        }
    }
}
```

---

#### Error Handling Pattern

```swift
// Good: Specific error handling with user feedback
@MainActor
func analyze() async {
    isProcessing = true
    defer { isProcessing = false }
    
    do {
        let result = try await engine.anonymizeText(originalText)
        
        anonymizedText = result.anonymizedText
        entities = result.entities
        applyHighlights(result)
        
        showSuccess("Analysis complete")
        
    } catch let error as AppError {
        // Handle our custom errors with specific messages
        alertTitle = "Analysis Failed"
        alertMessage = error.errorDescription ?? "An unknown error occurred"
        alertRecovery = error.recoverySuggestion
        showAlert = true
        
    } catch {
        // Handle unexpected errors gracefully
        alertTitle = "Unexpected Error"
        alertMessage = "An unexpected error occurred: \(error.localizedDescription)"
        alertRecovery = "Please try again or contact support if the issue persists."
        showAlert = true
    }
}

// Bad: Generic error handling
func analyze() async {
    do {
        let result = try await engine.anonymizeText(originalText)
        anonymizedText = result.anonymizedText
    } catch {
        print("Error: \(error)") // No user feedback!
    }
}
```

---

### 7.6 Async/Await Best Practices

#### Rules
1. **All network calls must be async** - Never block main thread
2. **Use @MainActor for UI updates** - Ensure thread safety
3. **Provide cancellation** - Long operations should be cancellable
4. **Use Task for concurrent work** - Don't block unnecessarily

#### Pattern: ViewModel with Async Operations

```swift
@MainActor
class AppViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var result: String = ""
    @Published var errorMessage: String?
    
    private var currentTask: Task<Void, Never>?
    
    func anonymize(text: String) {
        // Cancel any existing task
        currentTask?.cancel()
        
        // Create new task
        currentTask = Task {
            isProcessing = true
            defer { isProcessing = false }
            
            do {
                // Heavy work happens off main thread in OllamaService
                let result = try await ollamaService.sendRequest(text: text)
                
                // UI updates automatically on main thread because of @MainActor
                self.result = result
                self.errorMessage = nil
                
            } catch is CancellationError {
                // Task was cancelled, ignore
                return
                
            } catch {
                // Update error state
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
    }
}
```

---

#### Pattern: Service with Network Calls

```swift
class OllamaService: OllamaServiceProtocol {
    private let session: URLSession
    private let baseURL = URL(string: "http://localhost:11434")!
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    func sendRequest(text: String, systemPrompt: String) async throws -> String {
        let endpoint = baseURL.appendingPathComponent("/api/generate")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        let body = OllamaRequest(
            model: "llama3.1:8b",
            prompt: constructPrompt(text: text, systemPrompt: systemPrompt),
            stream: false,
            options: nil
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        // This is async and off main thread automatically
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkError(NSError(domain: "OllamaService", code: -1))
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw AppError.modelNotFound("llama3.1:8b")
            }
            throw AppError.networkError(
                NSError(domain: "HTTP", code: httpResponse.statusCode)
            )
        }
        
        let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return ollamaResponse.response
    }
}
```

---

### 7.7 Testing Strategy

#### Unit Tests Coverage Requirements

**Services (80%+ coverage required):**
- `OllamaServiceTests.swift`
  - Test successful requests
  - Test error cases (timeout, connection refused, 404)
  - Test request construction
  - Test response parsing

- `EntityMapperTests.swift`
  - Test consistency (same entity → same code)
  - Test counter increments
  - Test reset functionality
  - Test different entity types

- `AnonymizationEngineTests.swift`
  - Test end-to-end flow
  - Test with various text lengths
  - Test with edge cases (empty, very long, special characters)

**Utilities (70%+ coverage):**
- `HighlightHelperTests.swift`
  - Test range calculations
  - Test NSAttributedString creation
  - Test color application

#### Test Naming Convention

```swift
// Pattern: test[UnitOfWork]_[StateUnderTest]_[ExpectedBehavior]

func testEntityMapper_SameEntity_ReturnsConsistentCode() {
    // Arrange
    let mapper = EntityMapper()
    
    // Act
    let code1 = mapper.getCode(for: "Jane Smith", type: .person_client)
    let code2 = mapper.getCode(for: "Jane Smith", type: .person_client)
    
    // Assert
    XCTAssertEqual(code1, code2)
    XCTAssertEqual(code1, "CLIENT_A")
}

func testOllamaService_OllamaNotRunning_ThrowsCorrectError() async {
    // Arrange
    let service = OllamaService(session: MockURLSession(error: .connectionRefused))
    
    // Act & Assert
    do {
        _ = try await service.sendRequest(text: "test", systemPrompt: "test")
        XCTFail("Should have thrown error")
    } catch let error as AppError {
        XCTAssertEqual(error, .ollamaNotRunning)
    } catch {
        XCTFail("Wrong error type")
    }
}
```

---

### 7.8 Performance Guidelines

#### Memory Management

```swift
// Good: Proper cleanup
class AppViewModel: ObservableObject {
    @Published var originalText: String = ""
    private var cancellables = Set<AnyCancellable>()
    
    deinit {
        cancellables.removeAll()
    }
}

// Bad: Potential memory leak
class AppViewModel: ObservableObject {
    @Published var originalText: String = ""
    private var observation: NSKeyValueObservation?
    // No cleanup in deinit
}
```

#### Debouncing User Input

```swift
// Good: Debounced validation
class AppViewModel: ObservableObject {
    @Published var originalText: String = ""
    
    private var debounceTask: Task<Void, Never>?
    
    init() {
        $originalText
            .sink { [weak self] newValue in
                self?.debounceTask?.cancel()
                self?.debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    if !Task.isCancelled {
                        await self?.validateInput(newValue)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func validateInput(_ text: String) async {
        // Validation logic
    }
}
```

---

### 7.9 Security Checklist

**Before each release, verify:**

- [ ] No hardcoded secrets or API keys anywhere in code
- [ ] No logging of original text (even in debug mode)
- [ ] No file writes (search codebase for FileManager usage)
- [ ] No network calls except localhost:11434 (audit all URLSession usage)
- [ ] No analytics or telemetry code (search for any tracking SDKs)
- [ ] UserDefaults only stores non-sensitive data (setupCompleted flag only)
- [ ] Clipboard properly cleared on app quit (verify in testing)
- [ ] No temp files created (check /tmp directory after test runs)

**Code audit commands:**
```bash
# Check for file writes
grep -r "FileManager" . --include="*.swift"

# Check for external network calls
grep -r "URL(string:" . --include="*.swift" | grep -v "localhost"

# Check for logging sensitive data
grep -r "print(" . --include="*.swift" | grep -i "text\|original\|anonymized"
```

---

## 8. Brand Integration & Design System

### 8.1 3 Big Things Brand Values

**Core Principles:**
- Evidence-based and practical
- Privacy-first, ethical AI use
- New Zealand cultural competence
- Professional yet approachable
- Human-led technology

**Visual Language:**
- Clean, professional, warm
- Inspired by Aotearoa natural environment
- Harakeke (flax) as core symbol
- Interconnection and weaving metaphors

---

### 8.2 Complete Design System

**File:** `Utilities/DesignSystem.swift`

```swift
import SwiftUI

enum DesignSystem {
    
    // MARK: - Colors
    
    enum Colors {
        // Primary Brand Colors
        static let primaryTeal = Color(hex: "#0A6B7C")
        static let tealDark = Color(hex: "#045563")
        static let accentOrange = Color(hex: "#E68A2E")
        static let sand = Color(hex: "#D4AE80")
        static let sandLight = Color(hex: "#E8D4BC")
        
        // Supporting Colors
        static let warmWhite = Color(hex: "#FAF7F4")
        static let charcoal = Color(hex: "#2E2E2E")
        static let sage = Color(hex: "#A9C1B5")
        static let lightGray = Color(hex: "#F5F5F5")
        
        // Functional Colors
        static let background = Color(hex: "#FFFFFF")
        static let highlightYellow = Color.yellow.opacity(0.3)
        static let successGreen = Color(hex: "#A9C1B5")  // Using sage
        static let errorRed = Color(hex: "#DC3545")
        
        // Text Colors
        static let textPrimary = charcoal
        static let textSecondary = Color(hex: "#6C757D")
        static let textOnTeal = Color.white
        static let textOnOrange = Color.white
    }
    
    // MARK: - Typography
    
    enum Typography {
        // Headings (Lora serif font)
        static let title = Font.custom("Lora", size: 32).weight(.bold)
        static let subtitle = Font.custom("Lora", size: 24).weight(.semibold)
        static let heading = Font.custom("Lora", size: 18).weight(.medium)
        
        // Body text (Source Sans 3)
        static let body = Font.custom("SourceSans3-Regular", size: 13)
        static let bodyMedium = Font.custom("SourceSans3-Medium", size: 13)
        static let bodySemibold = Font.custom("SourceSans3-Semibold", size: 13)
        
        // UI elements
        static let button = Font.custom("SourceSans3-Semibold", size: 13)
        static let caption = Font.custom("SourceSans3-Regular", size: 11)
        static let small = Font.custom("SourceSans3-Regular", size: 9)
        
        // Monospace for clinical notes
        static let mono = Font.system(size: 12, design: .monospaced)
        static let monoLarge = Font.system(size: 13, design: .monospaced)
    }
    
    // MARK: - Spacing
    
    enum Spacing {
        static let tiny: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xlarge: CGFloat = 32
        static let xxlarge: CGFloat = 48
    }
    
    // MARK: - Layout
    
    enum Layout {
        // Window dimensions
        static let windowMinWidth: CGFloat = 900
        static let windowMinHeight: CGFloat = 600
        static let defaultWindowWidth: CGFloat = 1200
        static let defaultWindowHeight: CGFloat = 700
        
        // Component sizes
        static let buttonHeight: CGFloat = 32
        static let inputHeight: CGFloat = 36
        static let iconSize: CGFloat = 20
        
        // Radii
        static let cornerRadius: CGFloat = 8
        static let buttonCornerRadius: CGFloat = 6
        static let cardCornerRadius: CGFloat = 8
        
        // Borders
        static let borderWidth: CGFloat = 1
        static let dividerHeight: CGFloat = 2
    }
    
    // MARK: - Shadows
    
    enum Shadows {
        static let card = (color: Color.black.opacity(0.05), radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let button = (color: Color.black.opacity(0.1), radius: CGFloat(2), x: CGFloat(0), y: CGFloat(1))
        static let overlay = (color: Color.black.opacity(0.2), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
    }
    
    // MARK: - Animation
    
    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
    }
}

// MARK: - Color Extension for Hex Support

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
```

---

### 8.3 Button Styles

**File:** `Views/Components/ButtonStyles.swift`

```swift
import SwiftUI

// MARK: - Primary Button (Teal, for main actions)

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.button)
            .foregroundColor(DesignSystem.Colors.textOnTeal)
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.vertical, DesignSystem.Spacing.small)
            .frame(minHeight: DesignSystem.Layout.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.buttonCornerRadius)
                    .fill(buttonBackgroundColor(isPressed: configuration.isPressed))
            )
            .shadow(
                color: DesignSystem.Shadows.button.color,
                radius: DesignSystem.Shadows.button.radius,
                x: DesignSystem.Shadows.button.x,
                y: DesignSystem.Shadows.button.y
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.standard, value: configuration.isPressed)
    }
    
    private func buttonBackgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return DesignSystem.Colors.lightGray
        } else if isPressed {
            return DesignSystem.Colors.tealDark
        } else {
            return DesignSystem.Colors.primaryTeal
        }
    }
}

// MARK: - Secondary Button (Outlined)

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.button)
            .foregroundColor(foregroundColor(isPressed: configuration.isPressed))
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.vertical, DesignSystem.Spacing.small)
            .frame(minHeight: DesignSystem.Layout.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.buttonCornerRadius)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.buttonCornerRadius)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: DesignSystem.Layout.borderWidth)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.standard, value: configuration.isPressed)
    }
    
    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return DesignSystem.Colors.lightGray
        } else if isPressed {
            return DesignSystem.Colors.sage.opacity(0.2)
        } else {
            return Color.clear
        }
    }
    
    private func borderColor(isPressed: Bool) -> Color {
        isEnabled ? DesignSystem.Colors.charcoal : DesignSystem.Colors.lightGray
    }
    
    private func foregroundColor(isPressed: Bool) -> Color {
        isEnabled ? DesignSystem.Colors.charcoal : DesignSystem.Colors.textSecondary
    }
}

// MARK: - Accent Button (Orange, for copy/action)

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.button)
            .foregroundColor(DesignSystem.Colors.textOnOrange)
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.vertical, DesignSystem.Spacing.small)
            .frame(minHeight: DesignSystem.Layout.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.buttonCornerRadius)
                    .fill(buttonBackgroundColor(isPressed: configuration.isPressed))
            )
            .shadow(
                color: DesignSystem.Shadows.button.color,
                radius: DesignSystem.Shadows.button.radius,
                x: DesignSystem.Shadows.button.x,
                y: DesignSystem.Shadows.button.y
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.standard, value: configuration.isPressed)
    }
    
    private func buttonBackgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return DesignSystem.Colors.sand
        } else if isPressed {
            return DesignSystem.Colors.accentOrange.opacity(0.8)
        } else {
            return DesignSystem.Colors.accentOrange
        }
    }
}

// MARK: - Link Button (Text only, no background)

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.body)
            .foregroundColor(DesignSystem.Colors.primaryTeal)
            .underline()
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(DesignSystem.Animation.standard, value: configuration.isPressed)
    }
}
```

---

### 8.4 UI Component Examples

#### Card Component

```swift
struct Card<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(DesignSystem.Spacing.large)
            .background(DesignSystem.Colors.warmWhite)
            .cornerRadius(DesignSystem.Layout.cardCornerRadius)
            .shadow(
                color: DesignSystem.Shadows.card.color,
                radius: DesignSystem.Shadows.card.radius,
                x: DesignSystem.Shadows.card.x,
                y: DesignSystem.Shadows.card.y
            )
    }
}

// Usage:
Card {
    VStack(alignment: .leading) {
        Text("Card Title")
            .font(DesignSystem.Typography.heading)
        Text("Card content goes here")
            .font(DesignSystem.Typography.body)
    }
}
```

---

#### Status Indicator

```swift
struct StatusIndicator: View {
    enum Status {
        case ready
        case processing
        case success
        case error
        
        var color: Color {
            switch self {
            case .ready: return DesignSystem.Colors.sage
            case .processing: return DesignSystem.Colors.accentOrange
            case .success: return DesignSystem.Colors.successGreen
            case .error: return DesignSystem.Colors.errorRed
            }
        }
        
        var icon: String {
            switch self {
            case .ready: return "circle.fill"
            case .processing: return "arrow.triangle.2.circlepath"
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.circle.fill"
            }
        }
        
        var text: String {
            switch self {
            case .ready: return "Ready"
            case .processing: return "Processing..."
            case .success: return "Complete"
            case .error: return "Error"
            }
        }
    }
    
    let status: Status
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Image(systemName: status.icon)
                .foregroundColor(status.color)
                .imageScale(.small)
            
            Text(status.text)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.small)
    }
}
```

---

### 8.5 Font Loading (Required for Brand Fonts)

**Info.plist additions:**

```xml
<key>ATSApplicationFontsPath</key>
<string>Fonts</string>
<key>UIAppFonts</key>
<array>
    <string>Lora-Regular.ttf</string>
    <string>Lora-Medium.ttf</string>
    <string>Lora-SemiBold.ttf</string>
    <string>Lora-Bold.ttf</string>
    <string>SourceSans3-Regular.ttf</string>
    <string>SourceSans3-Medium.ttf</string>
    <string>SourceSans3-SemiBold.ttf</string>
</array>
```

**Note to developer:** Download fonts from Google Fonts:
- Lora: https://fonts.google.com/specimen/Lora
- Source Sans 3: https://fonts.google.com/specimen/Source+Sans+3

Place .ttf files in `ClinicalAnon/Resources/Fonts/` directory.

---

### 8.6 Dark Mode Support

All colors automatically support dark mode via SwiftUI's adaptive colors:

```swift
// Instead of defining separate dark mode colors, use system colors where appropriate
enum Colors {
    // These adapt automatically
    static let background = Color(NSColor.textBackgroundColor)
    static let textPrimary = Color(NSColor.labelColor)
    
    // Brand colors stay consistent in both modes
    static let primaryTeal = Color(hex: "#0A6B7C")  // Same in light/dark
    
    // Adjust opacity for dark mode
    static let cardBackground = Color(NSColor.controlBackgroundColor)
}
```

**Testing:** Always test in both light and dark mode during development.

---

## 9. Implementation Guide

### 9.1 Development Phases

#### Phase 1: Project Setup & Design System (Day 1)

**Tasks:**
1. Create new Xcode project
   - Product Name: ClinicalAnon
   - Organization: 3 Big Things
   - Interface: SwiftUI
   - Language: Swift
   - Target: macOS 12.0+

2. Setup project structure
   - Create folder groups per architecture (Views, ViewModels, Models, Services, Utilities)
   - Add Resources/Fonts folder

3. Implement DesignSystem.swift
   - Copy complete design system from section 8.2
   - Test color rendering

4. Download and integrate fonts
   - Download Lora and Source Sans 3 from Google Fonts
   - Add to project
   - Update Info.plist

5. Create AppError.swift
   - Copy from section 7.5
   - Test with simple throw/catch

**Deliverable:** Empty app that compiles with design system in place

---

#### Phase 2: Setup Flow & Ollama Integration (Days 2-3)

**Tasks:**
1. Implement SetupManager.swift
   - Detection functions (isOllamaInstalled, isModelDownloaded, etc.)
   - Installation triggers
   - Progress tracking

2. Create SetupView.swift
   - Wizard UI for setup steps
   - Progress indicators
   - Error states

3. Implement OllamaService.swift
   - Basic HTTP POST to localhost:11434
   - JSON encoding/decoding
   - Timeout handling

4. Update ClinicalAnonApp.swift
   - Conditional view rendering (Setup vs. Main)
   - UserDefaults for setup completion flag

**Test:** Run app, verify setup flow works end-to-end
- Detects missing Ollama
- Shows manual install instructions
- Detects Ollama when installed
- Triggers model download
- Shows progress
- Transitions to ready state

**Deliverable:** Working setup wizard

---

#### Phase 3: Core Data Models (Day 4)

**Tasks:**
1. Create Entity.swift
2. Create EntityType.swift
3. Create AnalysisResult.swift
4. Create OllamaRequest.swift
5. Create OllamaResponse.swift

**Test:** Verify all models conform to Codable, test JSON encoding/decoding

**Deliverable:** Complete data layer

---

#### Phase 4: Business Logic - Services (Days 5-6)

**Tasks:**
1. Complete OllamaService.swift
   - Full request/response cycle
   - Error handling for all cases
   - Timeout implementation

2. Implement EntityMapper.swift
   - Consistency logic
   - Counter management
   - Reset functionality

3. Create AnonymizationEngine.swift
   - Orchestrates OllamaService + EntityMapper
   - Parses LLM response
   - Builds AnalysisResult
   - Error handling

**Test:** Unit tests for each service
- Mock Ollama responses
- Test entity mapping consistency
- Test error propagation

**Deliverable:** Fully tested business logic layer

---

#### Phase 5: UI Components (Days 7-8)

**Tasks:**
1. Create button styles (PrimaryButtonStyle, SecondaryButtonStyle, etc.)
2. Create Card component
3. Create StatusIndicator component
4. Implement HighlightHelper.swift for text highlighting

**Test:** Create preview views for each component in different states

**Deliverable:** Reusable UI component library

---

#### Phase 6: Main App View (Days 9-10)

**Tasks:**
1. Create AppViewModel.swift
   - @Published properties for state
   - analyze(), clearAll(), copyToClipboard() methods
   - Error handling and user feedback

2. Create ContentView.swift
   - Two-pane layout (left original, right anonymized)
   - Button bar (Analyze, Clear All, Copy)
   - Status indicator
   - Warning banner

3. Implement text highlighting in both panes
   - Use NSAttributedString
   - Apply yellow highlights based on entity ranges

**Test:** Full workflow
1. Paste text
2. Click Analyze
3. Verify highlights appear
4. Edit anonymized text
5. Copy to clipboard
6. Clear all

**Deliverable:** Working main application interface

---

#### Phase 7: Integration & Polish (Days 11-12)

**Tasks:**
1. Connect all pieces (SetupView ↔ ContentView via app state)
2. Implement keyboard shortcuts (Cmd+Shift+C for copy)
3. Add alert dialogs for errors
4. Polish animations and transitions
5. Accessibility improvements (VoiceOver labels)

**Test:** Full end-to-end scenarios
- First launch → setup → use → quit → relaunch
- Error recovery (Ollama stops mid-analysis)
- Long text performance
- Very short text
- Edge cases (emoji, special characters)

**Deliverable:** Beta-ready application

---

#### Phase 8: Testing & Validation (Days 13-14)

**Tasks:**
1. Run full test suite (unit + UI tests)
2. Manual testing with real clinical notes
3. Test all error states
4. Test dark mode
5. Test accessibility features
6. Performance profiling (memory leaks, CPU usage)

**Test Cases:** Execute all scenarios from section 10.2

**Deliverable:** Release Candidate 1

---

#### Phase 9: Documentation & Deployment (Day 15)

**Tasks:**
1. Write user documentation
2. Create release notes
3. Code signing and notarization (for distribution)
4. Create installation package
5. Write README for GitHub (if open source)

**Deliverable:** Version 1.0 ready for deployment

---

### 9.2 Development Priorities

**Must Have (MVP):**
- ✅ Setup wizard for Ollama installation
- ✅ Single note anonymization
- ✅ Entity consistency within session
- ✅ Yellow highlighting
- ✅ Manual editing of anonymized text
- ✅ Copy to clipboard
- ✅ Error handling for common issues

**Should Have (v1.1):**
- Statistics display (X entities anonymized)
- Keyboard shortcuts for all actions
- Undo/redo in anonymized pane
- Export anonymized text to file with warning
- Preferences for default model or other settings

**Could Have (v2.0+):**
- Batch processing
- Consistent mapping across multiple documents
- Project-based sessions (save/load entity mappings)
- Custom entity types (user-defined)
- Alternative anonymization strategies (realistic names vs. codes)

---

### 9.3 Critical Implementation Notes

#### For AI Coding Assistant:

1. **SwiftUI Text Editors with Highlighting:**
   - Use `TextEditor` with `NSAttributedString`
   - Bind to custom `AttributedStringBinding`
   - Highlights applied via NSAttributedString background color

2. **Async/Await:**
   - All network calls MUST be async
   - ViewModels MUST be @MainActor
   - Use `Task { }` for concurrent work
   - Never block main thread

3. **No File I/O:**
   - If you're tempted to write to disk, STOP
   - All state in memory only
   - Check: No `FileManager.default.` calls anywhere

4. **Entity Mapping Persistence:**
   - Use @StateObject in ViewModel
   - EntityMapper survives view refreshes
   - Reset only on "Clear All" or app quit

5. **Error Handling:**
   - Use AppError enum for all errors
   - Always provide user-friendly messages
   - Include recovery suggestions

6. **Testing:**
   - Write unit tests for Services first
   - Mock OllamaService for ViewModel tests
   - UI tests for critical paths only

7. **Performance:**
   - Debounce text input validation
   - Use lazy loading for long text
   - Profile with Instruments regularly

---

## 10. Testing & Validation

### 10.1 Test Categories

#### Unit Tests (80%+ coverage target)

**OllamaServiceTests.swift:**
```swift
class OllamaServiceTests: XCTestCase {
    var service: OllamaService!
    var mockSession: MockURLSession!
    
    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        service = OllamaService(session: mockSession)
    }
    
    func testSendRequest_Success_ReturnsValidResponse() async throws {
        // Arrange
        let expectedJSON = """
        {
          "model": "llama3.1:8b",
          "created_at": "2024-01-01T00:00:00Z",
          "response": "{\\"anonymized_text\\":\\"[CLIENT_A] attended.\\",\\"entities\\":[]}",
          "done": true
        }
        """
        mockSession.data = expectedJSON.data(using: .utf8)
        mockSession.response = HTTPURLResponse(
            url: URL(string: "http://localhost:11434")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // Act
        let result = try await service.sendRequest(text: "Jane attended.", systemPrompt: "test")
        
        // Assert
        XCTAssertTrue(result.contains("CLIENT_A"))
    }
    
    func testSendRequest_OllamaNotRunning_ThrowsError() async {
        // Arrange
        mockSession.error = URLError(.cannotConnectToHost)
        
        // Act & Assert
        do {
            _ = try await service.sendRequest(text: "test", systemPrompt: "test")
            XCTFail("Should have thrown error")
        } catch let error as AppError {
            XCTAssertEqual(error, .ollamaNotRunning)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testSendRequest_Timeout_ThrowsTimeoutError() async {
        // Test timeout behavior
    }
    
    func testSendRequest_ModelNotFound_ThrowsCorrectError() async {
        // Test 404 response
    }
}
```

**EntityMapperTests.swift:**
```swift
class EntityMapperTests: XCTestCase {
    var mapper: EntityMapper!
    
    override func setUp() {
        super.setUp()
        mapper = EntityMapper()
    }
    
    func testGetCode_SameEntity_ReturnsConsistentCode() {
        // Act
        let code1 = mapper.getCode(for: "Jane Smith", type: .person_client)
        let code2 = mapper.getCode(for: "Jane Smith", type: .person_client)
        
        // Assert
        XCTAssertEqual(code1, code2)
        XCTAssertEqual(code1, "CLIENT_A")
    }
    
    func testGetCode_DifferentEntities_ReturnsIncrementedCodes() {
        // Act
        let code1 = mapper.getCode(for: "Jane", type: .person_client)
        let code2 = mapper.getCode(for: "John", type: .person_client)
        
        // Assert
        XCTAssertEqual(code1, "CLIENT_A")
        XCTAssertEqual(code2, "CLIENT_B")
    }
    
    func testGetCode_DifferentTypes_IndependentCounters() {
        // Act
        let clientCode = mapper.getCode(for: "Jane", type: .person_client)
        let providerCode = mapper.getCode(for: "Dr. Smith", type: .person_provider)
        
        // Assert
        XCTAssertEqual(clientCode, "CLIENT_A")
        XCTAssertEqual(providerCode, "PROVIDER_A")
    }
    
    func testReset_ClearsAllMappings() {
        // Arrange
        _ = mapper.getCode(for: "Jane", type: .person_client)
        
        // Act
        mapper.reset()
        let newCode = mapper.getCode(for: "Jane", type: .person_client)
        
        // Assert
        XCTAssertEqual(newCode, "CLIENT_A") // Counter reset
    }
}
```

**AnonymizationEngineTests.swift:**
```swift
class AnonymizationEngineTests: XCTestCase {
    var engine: AnonymizationEngine!
    var mockOllamaService: MockOllamaService!
    var mockEntityMapper: MockEntityMapper!
    
    override func setUp() {
        super.setUp()
        mockOllamaService = MockOllamaService()
        mockEntityMapper = MockEntityMapper()
        engine = AnonymizationEngine(
            ollamaService: mockOllamaService,
            entityMapper: mockEntityMapper
        )
    }
    
    func testAnonymizeText_ValidInput_ReturnsAnalysisResult() async throws {
        // Arrange
        mockOllamaService.mockResponse = """
        {
          "anonymized_text": "[CLIENT_A] attended session.",
          "entities": [{
            "original": "Jane",
            "replacement": "CLIENT_A",
            "type": "person_client",
            "positions": [[0, 4]]
          }]
        }
        """
        
        // Act
        let result = try await engine.anonymizeText("Jane attended session.")
        
        // Assert
        XCTAssertEqual(result.anonymizedText, "[CLIENT_A] attended session.")
        XCTAssertEqual(result.entities.count, 1)
        XCTAssertEqual(result.entities.first?.original, "Jane")
    }
    
    func testAnonymizeText_InvalidJSON_ThrowsParsingError() async {
        // Arrange
        mockOllamaService.mockResponse = "not valid json"
        
        // Act & Assert
        do {
            _ = try await engine.anonymizeText("test")
            XCTFail("Should have thrown error")
        } catch let error as AppError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("Wrong error type")
        }
    }
}
```

---

### 10.2 End-to-End Test Scenarios

#### Test Case 1: Basic Name Replacement

**Input:**
```
Jane Smith came to the clinic. Dr. Wilson saw Jane for 50 minutes.
```

**Expected Output:**
```
[CLIENT_A] came to the clinic. [PROVIDER_A] saw [CLIENT_A] for 50 minutes.
```

**Validation:**
- ✓ "Jane Smith" → CLIENT_A
- ✓ "Jane" → CLIENT_A (consistency)
- ✓ "Dr. Wilson" → PROVIDER_A
- ✓ Duration preserved ("50 minutes")

---

#### Test Case 2: Māori Names

**Input:**
```
Aroha Te Whare discussed whakamā (shame) with her therapist Kahu at the Te Arawa marae.
```

**Expected Output:**
```
[CLIENT_A] discussed whakamā (shame) with her therapist [PROVIDER_A] at the [LOCATION_A].
```

**Validation:**
- ✓ Māori names detected
- ✓ "whakamā" preserved (concept, not name)
- ✓ "Te Arawa marae" identified as location

---

#### Test Case 3: Context Disambiguation

**Input:**
```
Dawn woke at dawn feeling anxious.
```

**Expected Output:**
```
[CLIENT_A] woke at dawn feeling anxious.
```

**Validation:**
- ✓ First "Dawn" is name → anonymized
- ✓ Second "dawn" is time → preserved

---

#### Test Case 4: Dates & Timeframes

**Input:**
```
Client born 15 March 1985. Symptoms started in early 2024, about 6 months ago.
```

**Expected Output:**
```
Client born [DATE_A]. Symptoms started in early 2024, about 6 months ago.
```

**Validation:**
- ✓ Specific date anonymized
- ✓ General timeframe preserved

---

#### Test Case 5: Locations (Specific vs. General)

**Input:**
```
Lives at 123 Queen St, Hamilton. Works in the CBD. Grew up in a rural area.
```

**Expected Output:**
```
Lives at [LOCATION_A], [LOCATION_B]. Works in the CBD. Grew up in a rural area.
```

**Validation:**
- ✓ Specific address anonymized
- ✓ City anonymized
- ✓ General terms preserved

---

#### Test Case 6: Organizations

**Input:**
```
Works for Microsoft. Referred by Kāinga Ora. Sees counselor at their employer's EAP.
```

**Expected Output:**
```
Works for [ORGANIZATION_A]. Referred by [ORGANIZATION_B]. Sees counselor at their employer's EAP.
```

**Validation:**
- ✓ Specific organizations anonymized
- ✓ Generic "employer" preserved

---

#### Test Case 7: Family Relationships

**Input:**
```
Sarah brought her daughter Emma (7) and son Tom (10) to the session.
```

**Expected Output:**
```
[CLIENT_A] brought her daughter [CLIENT_B] (7) and son [CLIENT_C] (10) to the session.
```

**Validation:**
- ✓ All family members anonymized
- ✓ Ages preserved
- ✓ Relationships preserved

---

#### Test Case 8: Clinical Information Preservation

**Input:**
```
34-year-old female presenting with major depressive disorder. Using CBT techniques. Session duration: 50 minutes.
```

**Expected Output:**
```
34-year-old female presenting with major depressive disorder. Using CBT techniques. Session duration: 50 minutes.
```

**Validation:**
- ✓ Age preserved
- ✓ Gender preserved
- ✓ Diagnosis preserved
- ✓ Treatment approach preserved
- ✓ Duration preserved
- ✓ NO changes (no identifying info)

---

#### Test Case 9: Manual Editing

**Steps:**
1. Analyze text with "Jane Smith"
2. LLM produces "[CLIENT_A]"
3. User manually edits to "[PARTICIPANT_A]"
4. Copy to clipboard

**Expected:**
- ✓ Edit accepted
- ✓ Highlight removed from edited portion
- ✓ Clipboard contains manual edit

---

#### Test Case 10: Clear All

**Steps:**
1. Analyze text ("Jane" → CLIENT_A)
2. Click "Clear All"
3. Paste new text with "Jane"
4. Analyze

**Expected:**
- ✓ Both panes cleared
- ✓ Highlights removed
- ✓ "Jane" becomes CLIENT_A again (counter reset)

---

### 10.3 Error Scenario Tests

#### Test Error 1: Ollama Not Installed
- **Trigger:** Ollama not present on system
- **Expected:** Setup screen shown with install instructions

#### Test Error 2: Ollama Not Running
- **Trigger:** Ollama installed but not running
- **Expected:** Error alert: "Ollama service not running. Start with: ollama serve"

#### Test Error 3: Model Not Downloaded
- **Trigger:** Ollama running but llama3.1:8b missing
- **Expected:** Download screen shown with progress bar

#### Test Error 4: Timeout
- **Trigger:** Very long text or slow LLM response
- **Expected:** After 30s, error alert: "Request timed out. Try shorter text."

#### Test Error 5: Invalid JSON from LLM
- **Trigger:** LLM returns malformed JSON
- **Expected:** Error alert: "Could not process text. Please try again."

---

### 10.4 Performance Tests

#### Test Perf 1: Short Text (<500 words)
- **Expected:** Analysis complete in <5 seconds

#### Test Perf 2: Medium Text (500-2000 words)
- **Expected:** Analysis complete in <10 seconds

#### Test Perf 3: Long Text (2000-10000 words)
- **Expected:** Analysis complete in <30 seconds OR user-friendly progress

#### Test Perf 4: Memory Usage
- **Test:** Run 10 analyses in a row
- **Expected:** Memory usage stable (<2GB), no leaks

#### Test Perf 5: UI Responsiveness
- **Test:** During analysis, try scrolling, clicking buttons
- **Expected:** UI remains responsive (no beach ball)

---

### 10.5 Accessibility Tests

#### Test A11y 1: VoiceOver
- **Test:** Navigate app using VoiceOver
- **Expected:** All elements properly labeled, navigation logical

#### Test A11y 2: Keyboard Navigation
- **Test:** Complete full workflow using only keyboard
- **Expected:** All actions accessible via Tab/Enter/Cmd shortcuts

#### Test A11y 3: Color Contrast
- **Test:** Measure contrast ratios with accessibility inspector
- **Expected:** All text meets WCAG AA (4.5:1 minimum)

#### Test A11y 4: Dynamic Type
- **Test:** Change system text size in preferences
- **Expected:** App text scales appropriately, layout doesn't break

---

### 10.6 Security Audit

**Before release, verify:**

```bash
# 1. No hardcoded secrets
grep -r "apiKey\|password\|secret\|token" . --include="*.swift"

# 2. No file writes
grep -r "FileManager\|write\|save" . --include="*.swift"

# 3. No external network calls
grep -r "URL(string:" . --include="*.swift" | grep -v "localhost"

# 4. No logging of sensitive data
grep -r "print\|NSLog" . --include="*.swift" | grep -i "text\|original"

# 5. No analytics/tracking
grep -r "analytics\|tracking\|telemetry" . --include="*.swift"
```

**Manual checks:**
- [ ] Run app with network completely off (works after setup)
- [ ] Check /tmp directory after test run (no files created)
- [ ] Monitor network traffic with Charles Proxy (no unexpected calls)
- [ ] Check UserDefaults after quit (only setupCompleted flag)

---

## 11. Security & Privacy

### 11.1 Privacy Architecture

#### Core Principles
1. **Local-only processing** - No cloud uploads, ever
2. **No persistence** - Nothing written to disk
3. **Memory-only state** - All data in RAM, cleared on quit
4. **No logging** - Original text never logged, even in debug
5. **No analytics** - No tracking, telemetry, or usage data collection

---

### 11.2 Data Flow Diagram

```
User Pastes Text
      ↓
  [RAM Only]
      ↓
AppViewModel.originalText: String
      ↓
  [RAM Only]
      ↓
AnonymizationEngine.anonymizeText()
      ↓
  [RAM Only] → [localhost:11434] → [RAM Only]
      ↓                ↓                ↓
  Original      Sent to Ollama    Anonymized
  (in memory)   (local process)   (in memory)
      ↓                                ↓
  [Display]                      [Display]
      ↓                                ↓
User Reviews                   User Copies
      ↓                                ↓
[Clipboard]                    [Clipboard]
      ↓                                ↓
User Quits App                 User Quits App
      ↓                                ↓
[Memory Cleared]               [Memory Cleared]
      ↓                                ↓
[Clipboard Managed             [Clipboard Managed
 by macOS]                      by macOS]

NO DISK WRITES AT ANY STAGE
```

---

### 11.3 Security Implementation Checklist

#### ✅ Implemented Security Measures

**1. Local Processing Only**
```swift
// OllamaService only connects to localhost
private let baseURL = URL(string: "http://localhost:11434")!

// No external network calls anywhere in codebase
// Enforced by code review
```

**2. No File Persistence**
```swift
// NO FileManager usage anywhere
// Search codebase: grep -r "FileManager" returns 0 results

// UserDefaults ONLY for non-sensitive data
@AppStorage("setupCompleted") private var setupCompleted = false
// Does NOT store: text, entities, mappings
```

**3. Memory-Only State**
```swift
@MainActor
class AppViewModel: ObservableObject {
    @Published var originalText: String = ""        // RAM only
    @Published var anonymizedText: String = ""      // RAM only
    
    // No @AppStorage, no disk writes
    // State lives only while app is open
}
```

**4. No Logging of Sensitive Data**
```swift
// Debug logging NEVER includes actual text
func anonymize() async {
    print("Starting anonymization...") // ✅ Safe
    // print("Text: \(originalText)")  // ❌ NEVER do this
    
    do {
        let result = try await engine.anonymizeText(originalText)
        print("Anonymization successful") // ✅ Safe
    } catch {
        print("Error: \(error.localizedDescription)") // ✅ Safe (no text)
    }
}
```

**5. Clipboard Handling**
```swift
// Copying is user-initiated and explicit
func copyToClipboard() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(anonymizedText, forType: .string)
    
    // macOS manages clipboard lifecycle
    // App does NOT monitor or persist clipboard
}
```

---

### 11.4 Privacy Policy Summary

**For User Documentation:**

> **ClinicalAnon Privacy Guarantee**
>
> **What happens to your data:**
> - Your clinical notes are processed **only on your Mac**
> - Nothing is ever uploaded to the internet or cloud services
> - Nothing is saved to files on your hard drive
> - All processing happens in memory (RAM) while the app is open
> - When you close the app, all data is immediately cleared
>
> **What we DON'T do:**
> - We don't collect any usage data or analytics
> - We don't log your text or notes
> - We don't send anything to external servers
> - We don't require an account or login
> - We don't track you in any way
>
> **How it works:**
> - Text is sent only to Ollama, which runs locally on your Mac
> - Ollama processes the text using a model stored on your Mac
> - The anonymized result stays on your Mac
> - You control what happens next (copy, edit, or clear)
>
> **Your responsibility:**
> - Review anonymized text carefully before sharing
> - The tool assists anonymization but you are responsible for final review
> - Manual edits are not tracked - double-check before sharing

---

### 11.5 Threat Model & Mitigations

#### Threat 1: Data Exfiltration via Network
**Risk:** Text sent to external server

**Mitigation:**
- All network calls hardcoded to localhost:11434
- No external network dependencies
- Code review enforces no additional network calls
- User can verify by running with network off (works fine)

**Residual Risk:** None (after setup)

---

#### Threat 2: Data Persistence on Disk
**Risk:** Text written to file system

**Mitigation:**
- No FileManager usage anywhere in code
- No Core Data or other persistence frameworks
- No temp files created
- Search codebase for "write", "save", "FileManager" returns zero results (except in this spec doc)

**Residual Risk:** None

---

#### Threat 3: Clipboard Data Leakage
**Risk:** Sensitive data left in clipboard

**Mitigation:**
- Clipboard managed by macOS, not app
- User chooses when to copy (explicit action)
- Warning in UI: "Review carefully before sharing"
- macOS clipboard history can be cleared by user if desired

**Residual Risk:** Low (user-controlled)

---

#### Threat 4: Memory Dumps
**Risk:** Text extracted from RAM via memory dump

**Mitigation:**
- macOS security protections (requires admin/root)
- Strings cleared when app quits (automatic in Swift)
- No sensitive data in UserDefaults or plists

**Residual Risk:** Low (requires system compromise)

---

#### Threat 5: LLM Prompt Injection
**Risk:** Malicious text tricks LLM into bad behavior

**Mitigation:**
- LLM runs locally (no remote attack surface)
- Output validated (must be valid JSON)
- User reviews output before using
- LLM has no access to system commands or files

**Residual Risk:** Very Low (local, sandboxed)

---

#### Threat 6: Supply Chain Attack (Dependencies)
**Risk:** Malicious code in dependencies

**Mitigation:**
- Zero external dependencies (pure Swift/SwiftUI)
- Only dependency: Ollama (user installs separately, open source)
- No npm, CocoaPods, or other package managers

**Residual Risk:** Minimal (only Ollama)

---

### 11.6 Audit & Verification

**For Independent Audit:**

1. **Network Traffic Analysis:**
   ```bash
   # Install Charles Proxy or similar
   # Run ClinicalAnon
   # Paste and analyze text
   # Verify: Only connections to 127.0.0.1:11434
   ```

2. **File System Monitoring:**
   ```bash
   # Install fswatch or similar
   # Monitor file writes while app running
   # Verify: No files created except in /var/folders (macOS system files)
   ```

3. **Source Code Audit:**
   ```bash
   # Clone repository
   # Search for privacy-impacting code
   grep -r "URLSession\|FileManager\|write\|save\|analytics" . --include="*.swift"
   # Manual review of any results
   ```

4. **Binary Analysis:**
   ```bash
   # Extract strings from compiled binary
   strings ClinicalAnon.app/Contents/MacOS/ClinicalAnon | grep -i "http\|api\|key\|token"
   # Verify: No API keys, no external URLs
   ```

---

## 12. Deployment & User Guide

### 12.1 Pre-Deployment Checklist

**Before releasing v1.0:**

- [ ] All unit tests passing (80%+ coverage)
- [ ] All UI tests passing
- [ ] Manual testing complete (all test cases in section 10)
- [ ] Security audit complete (section 11)
- [ ] Performance profiling done (no memory leaks, acceptable speed)
- [ ] Accessibility validated (VoiceOver, keyboard, contrast)
- [ ] Dark mode tested
- [ ] Code signing certificate obtained
- [ ] App notarized by Apple
- [ ] User documentation written
- [ ] Release notes prepared
- [ ] Known issues documented

---

### 12.2 Code Signing & Notarization

#### Step 1: Obtain Developer Certificate
1. Join Apple Developer Program ($99/year)
2. Create Developer ID Application certificate
3. Download and install in Keychain

#### Step 2: Code Sign the App
```bash
# Sign the app bundle
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
  --options runtime \
  ClinicalAnon.app

# Verify signature
codesign --verify --deep --verbose ClinicalAnon.app
spctl --assess --verbose ClinicalAnon.app
```

#### Step 3: Notarize with Apple
```bash
# Create a zip for notarization
ditto -c -k --keepParent ClinicalAnon.app ClinicalAnon.zip

# Submit for notarization
xcrun notarytool submit ClinicalAnon.zip \
  --apple-id "your-apple-id@example.com" \
  --password "app-specific-password" \
  --team-id "YOUR_TEAM_ID" \
  --wait

# Staple the notarization ticket
xcrun stapler staple ClinicalAnon.app
```

---

### 12.3 Distribution Options

#### Option 1: Direct Download (Recommended for v1.0)
**Pros:**
- Full control over updates
- No App Store review delays
- Can include setup instructions

**Cons:**
- Users must handle security warnings
- Manual update process

**Setup:**
1. Create DMG installer with background image
2. Host on website with download link
3. Provide installation instructions

#### Option 2: Mac App Store
**Pros:**
- Easier installation for users
- Automatic updates
- More discoverable

**Cons:**
- Sandboxing restrictions may complicate Ollama integration
- Review process can take weeks
- 30% revenue share (if paid app)

**Not recommended for v1.0** due to Ollama setup complexity.

---

### 12.4 Installation Package Creation

#### Create DMG Installer

```bash
# Create a temporary DMG
hdiutil create -volname "ClinicalAnon" \
  -srcfolder ClinicalAnon.app \
  -ov -format UDZO \
  ClinicalAnon-Temp.dmg

# Mount it
hdiutil attach ClinicalAnon-Temp.dmg

# Customize appearance (optional)
# Add background image, position icons

# Convert to final DMG
hdiutil convert ClinicalAnon-Temp.dmg \
  -format UDZO \
  -o ClinicalAnon-v1.0.dmg

# Cleanup
hdiutil detach /Volumes/ClinicalAnon
rm ClinicalAnon-Temp.dmg
```

---

### 12.5 User Documentation

#### Quick Start Guide

**Title:** Getting Started with ClinicalAnon

**Step 1: Download and Install**
1. Download ClinicalAnon-v1.0.dmg from [website]
2. Open the DMG file
3. Drag ClinicalAnon to your Applications folder
4. Eject the DMG

**Step 2: First Launch Setup**
1. Double-click ClinicalAnon in Applications
2. If you see a security warning, right-click → Open
3. The setup wizard will check for Ollama
4. If needed, install Ollama:
   - Automatic: Click "Install Ollama Automatically" (requires admin password)
   - Manual: Open Terminal, paste: `brew install ollama`
5. Download the AI model (~4.7 GB, one-time)
6. Wait for download to complete

**Step 3: Anonymize Your First Note**
1. Copy your clinical note to clipboard
2. Paste into the left pane of ClinicalAnon
3. Click "Analyze"
4. Review the highlighted changes
5. Edit the anonymized version if needed (right pane)
6. Click "Copy Anonymized" when satisfied
7. Paste wherever you need the anonymized version

**Step 4: Clear and Start Fresh**
- Click "Clear All" to reset for a new note
- Entity codes start over (CLIENT_A, etc.)

---

#### FAQ

**Q: Is my data sent to the cloud?**
A: No. All processing happens locally on your Mac. Nothing is ever uploaded to the internet.

**Q: What happens to my notes when I close the app?**
A: Everything is immediately cleared from memory. Nothing is saved.

**Q: Can I use this offline?**
A: Yes, after the initial setup (which requires internet to download Ollama and the model), ClinicalAnon works completely offline.

**Q: Why does the first analysis take longer?**
A: The AI model needs to load into memory. Subsequent analyses are faster.

**Q: Can I trust the anonymization?**
A: ClinicalAnon is a tool to *assist* anonymization, but you must always review the output. The AI is very good but not perfect. You are responsible for the final check.

**Q: What if the AI misses something?**
A: You can manually edit the anonymized text in the right pane before copying. Review carefully.

**Q: Can I save my work?**
A: No. This is a privacy feature. Nothing is saved to ensure no accidental data retention.

**Q: Why does it need Ollama?**
A: Ollama is the local AI engine that powers the anonymization. It's open source and runs entirely on your Mac.

**Q: How much disk space do I need?**
A: About 5 GB for Ollama and the AI model. The app itself is ~20 MB.

**Q: Does this work on Intel Macs?**
A: Yes, though it's optimized for Apple Silicon (M1/M2/M3). Intel Macs will be slower.

**Q: Can I use a different AI model?**
A: v1.0 only supports llama3.1:8b. Future versions may add model selection.

**Q: Is this HIPAA compliant?**
A: ClinicalAnon is designed with privacy in mind (local processing, no storage), but HIPAA compliance depends on your organization's policies and how you use the tool. Consult your compliance officer.

---

### 12.6 Support & Troubleshooting

#### Common Issues

**Issue: "Ollama not detected" error**
- **Solution 1:** Open Terminal, run: `ollama serve`
- **Solution 2:** Restart ClinicalAnon
- **Solution 3:** Reinstall Ollama: `brew reinstall ollama`

**Issue: Slow analysis (>30 seconds)**
- **Cause:** Very long text or slow computer
- **Solution 1:** Split text into smaller chunks
- **Solution 2:** Close other heavy apps to free resources
- **Solution 3:** Check if Ollama is running: `ps aux | grep ollama`

**Issue: "Model not found" error**
- **Solution:** Download model manually:
  ```bash
  ollama pull llama3.1:8b
  ```

**Issue: Highlights not showing**
- **Cause:** macOS rendering issue
- **Solution:** Restart ClinicalAnon

**Issue: Can't copy to clipboard**
- **Cause:** macOS permissions issue
- **Solution:** System Preferences → Security & Privacy → Privacy → Accessibility → Add ClinicalAnon

---

### 12.7 Release Notes Template

#### ClinicalAnon v1.0 - Initial Release

**Release Date:** [Date]

**What's New:**
- ✨ Local-first clinical text anonymization
- 🔒 Complete privacy: no cloud uploads, no data retention
- 🎯 Consistent entity replacement within sessions
- 🇳🇿 New Zealand cultural competence (te reo Māori support)
- 🖍️ Visual highlighting of detected entities
- ✏️ Manual editing of anonymized output
- 🚀 Guided setup for Ollama installation

**System Requirements:**
- macOS 12 (Monterey) or later
- 8 GB RAM minimum (16 GB recommended)
- 5 GB free disk space for Ollama and AI model
- Internet connection for initial setup only

**Known Issues:**
- Very long texts (>10,000 words) may be slow to process
- Some Māori names with macrons may need manual review
- First analysis after app launch takes longer (model loading)

**Privacy:**
- Zero data collection or analytics
- All processing happens locally
- Nothing is saved to disk
- See full privacy policy: [link]

**Getting Started:**
1. Download and install ClinicalAnon
2. Follow setup wizard to install Ollama
3. Start anonymizing!

**Support:**
- Email: support@3bigthings.co.nz
- Documentation: [link]
- Known issues: [link]

---

### 12.8 Update Strategy

#### Versioning Scheme
- **Major (1.0 → 2.0):** Breaking changes, major new features
- **Minor (1.0 → 1.1):** New features, no breaking changes
- **Patch (1.0.0 → 1.0.1):** Bug fixes only

#### Future Roadmap

**v1.1 (Q2 2025):**
- Statistics display (entities anonymized count)
- Export to file with warning dialog
- Keyboard shortcut customization
- Undo/redo in anonymized pane

**v1.2 (Q3 2025):**
- Batch processing (multiple notes at once)
- Preferences panel
- Alternative replacement strategies
- Model selection

**v2.0 (Q4 2025):**
- Project-based sessions (save entity mappings)
- Collaboration features (shared anonymization keys)
- Enhanced NZ-specific entity detection
- Performance improvements

---

## Appendix A: Complete File Listing

**For AI Developer: Generate these files in this order**

1. `Utilities/DesignSystem.swift` - Design constants
2. `Utilities/AppError.swift` - Error definitions
3. `Models/EntityType.swift` - Entity type enum
4. `Models/Entity.swift` - Entity data structure
5. `Models/AnalysisResult.swift` - Result structure
6. `Models/OllamaRequest.swift` - API request models
7. `Models/OllamaResponse.swift` - API response models
8. `Services/OllamaService.swift` - HTTP communication
9. `Services/EntityMapper.swift` - Entity consistency
10. `Services/AnonymizationEngine.swift` - Core logic
11. `Utilities/HighlightHelper.swift` - Text highlighting
12. `Utilities/SetupManager.swift` - Ollama setup
13. `Views/Components/ButtonStyles.swift` - Button styles
14. `Views/Components/StatusIndicator.swift` - Status component
15. `Views/SetupView.swift` - Setup wizard UI
16. `ViewModels/AppViewModel.swift` - Main ViewModel
17. `Views/ContentView.swift` - Main app UI
18. `ClinicalAnonApp.swift` - App entry point
19. `Tests/` - Unit tests (after main implementation)

---

## Appendix B: Glossary

**Clinical Note:** Written documentation of a therapy session or clinical interaction

**Entity:** A piece of information that identifies a person, place, organization, or other identifying detail

**Anonymization:** The process of removing or replacing identifying information

**De-identification:** Similar to anonymization; removing identifiable information

**Ollama:** Open-source tool for running large language models locally

**LLM:** Large Language Model; AI trained on text data

**Llama 3.1:** Specific LLM model by Meta, used for anonymization

**Entity Mapping:** The consistent replacement of the same entity with the same code

**Harakeke:** Māori word for flax; inspiration for 3 Big Things logo

**Te reo Māori:** Māori language; official language of New Zealand

**WCAG:** Web Content Accessibility Guidelines; standards for accessibility

**NSAttributedString:** macOS text type that supports styling (colors, fonts)

**@MainActor:** Swift annotation ensuring code runs on main thread (for UI updates)

**async/await:** Swift pattern for asynchronous programming

---

## Appendix C: Contact & Support

**Development Team:**
- Email: dev@3bigthings.co.nz
- GitHub: [if open source]

**End User Support:**
- Email: support@3bigthings.co.nz
- Documentation: https://3bigthings.co.nz/clinicalanon

**Security Issues:**
- Email: security@3bigthings.co.nz
- PGP Key: [if applicable]

---

## Document Control

**Version:** 1.0  
**Last Updated:** October 2025  
**Status:** Approved for Development  
**Next Review:** Upon v1.0 Release  
**Owner:** 3 Big Things Development Team  
**Approved By:** [Name], Co-CEO

---

**END OF SPECIFICATION DOCUMENT**

---

## Instructions for AI Developer

You now have the complete specification for ClinicalAnon. Here's how to proceed:

1. **Read this entire document carefully**
2. **Start with Phase 1** (Design System setup)
3. **Follow the file creation order** in Appendix A
4. **Implement one phase at a time**, testing as you go
5. **Refer back to this spec** whenever you're unsure about requirements
6. **Follow all development standards** from Section 7
7. **Apply brand colors and typography** from Section 8
8. **Write tests** as specified in Section 10
9. **Run security checklist** from Section 11 before considering complete

**Questions to ask before starting each phase:**
- Do I understand all requirements for this phase?
- Have I read the relevant sections of the spec?
- Do I know what "done" looks like for this phase?
- What are the success criteria?

**Critical Success Factors:**
✅ 100% local processing (no cloud calls)  
✅ No disk writes (privacy first)  
✅ Entity consistency within session  
✅ Brand colors and typography applied  
✅ Accessible and polished UI  
✅ Comprehensive error handling  
✅ All tests passing

Good luck! Build something great. 🚀