# Swift NER + NZ Custom Recognizers - Design Document

**Project**: ClinicalAnon - Redactor
**Date**: 2025-10-21
**Purpose**: Add deterministic pattern-based entity detection for NZ clinical text

## Overview

Add a Swift-native entity detection system alongside the existing AI model approach, providing:
- **Fast, deterministic detection** (no LLM overhead)
- **NZ-specific patterns** (Māori names, NHI numbers, NZ addresses)
- **Offline capability** (no external services)
- **Hybrid mode** (combine AI + patterns for best accuracy)

## Architecture

```
DetectionService (Protocol)
├── AI Mode: OllamaService (existing)
└── Deterministic Mode: SwiftNERService (new)
    ├── Apple NER (baseline names, places, orgs)
    ├── NZ Pattern Recognizers
    │   ├── MaoriNameRecognizer
    │   ├── NZPhoneRecognizer
    │   ├── NZMedicalIDRecognizer
    │   ├── NZAddressRecognizer
    │   ├── RelationshipNameExtractor
    │   └── DateRecognizer
    └── Optional: Custom Create ML model (if needed)
```

## Why Swift NER Over Presidio?

### Presidio Challenges
- **Large bundle size**: 150-250MB (Python runtime + dependencies)
- **US-centric patterns**: SSN, zip codes - not relevant for NZ
- **Gatekeeper issues**: Unsigned binaries may be blocked on macOS
- **Complexity**: External process management, Python version conflicts

### Swift NER Advantages
- **Zero dependencies**: Uses Apple's built-in frameworks
- **Small footprint**: No app size increase
- **Fast**: Native Swift, no subprocess overhead
- **Customizable**: Easy to add NZ-specific patterns
- **Maintainable**: Pure Swift code, no Python bridge

### What About Apple NER's Limitations?

**Challenge**: Apple's NER not trained on NZ/Māori data

**Solution**: Hybrid approach
1. Use Apple NER for baseline (common English names, places)
2. Add custom recognizers for NZ-specific entities
3. Pattern matching for structured data (phones, IDs, dates)
4. Dictionary lookup for Māori names
5. Relationship extraction ("sister Margaret" → extract "Margaret")

## Implementation Phases

### Phase 1: Core Service Architecture (1-2 days)

**Files to Create**:
- `Services/SwiftNERService.swift` - Main service implementing DetectionServiceProtocol
- `Services/EntityRecognizer.swift` - Protocol for all recognizers

**Goal**: Establish service structure, run multiple recognizers, deduplicate results

### Phase 2: Foundation Recognizers (1 day)

**Files to Create**:
- `Services/Recognizers/AppleNERRecognizer.swift` - Wrap NLTagger
- `Services/Recognizers/PatternRecognizer.swift` - Base class for regex recognizers

**Goal**: Get Apple's baseline name/place/org detection working

### Phase 3: Māori Name Recognition (1-2 days)

**File to Create**:
- `Services/Recognizers/MaoriNameRecognizer.swift`

**Strategy**:
1. Dictionary of common Māori first names (Wiremu, Aroha, Hemi, etc.)
2. Dictionary of common Māori surnames/second names
3. Phonetic pattern matching (words with 'wh', 'ng', high vowel density)

**Confidence Levels**:
- Dictionary match: 0.95 (high confidence)
- Phonetic pattern: 0.6 (lower confidence)

### Phase 4: Relationship Name Extractor (1-2 days)

**File to Create**:
- `Services/Recognizers/RelationshipNameExtractor.swift`

**Critical for Clinical Text**:
Extracts names from relationship patterns:
- "sister Margaret" → "Margaret" (0.9 confidence)
- "mother Sofia and other sisters, Brenda and Natasha" → "Sofia", "Brenda", "Natasha"
- "friend David" → "David"

**Relationship Words**:
mother, father, sister, brother, son, daughter, wife, husband, partner, friend, flatmate, uncle, aunt, cousin, grandmother, grandfather, whanau, colleague

### Phase 5: NZ-Specific Pattern Recognizers (1-2 days)

**Files to Create**:
- `Services/Recognizers/NZPhoneRecognizer.swift`
- `Services/Recognizers/NZMedicalIDRecognizer.swift`
- `Services/Recognizers/NZAddressRecognizer.swift`
- `Services/Recognizers/DateRecognizer.swift`

**Patterns**:

**NZ Phone Numbers**:
- Mobile: `021/022/027/029-XXX-XXXX` (confidence: 0.95)
- Landline: `0X-XXX-XXXX` (confidence: 0.9)
- International: `+64 X XXX XXXX` (confidence: 0.95)

**NZ Medical IDs**:
- NHI: `ABC1234` (3 letters + 4 digits, confidence: 0.85)
- ACC case: `ACC12345` (confidence: 0.9)
- Generic ID: `ID #12345`, `MRN: 67890` (confidence: 0.8)

**NZ Addresses**:
- Street: `123 High Street` (confidence: 0.9)
- Auckland suburbs: Otahuhu, Manukau, Papatoetoe, Mangere, Mt Eden, Ponsonby, Parnell (confidence: 0.95)

**Dates**:
- DD/MM/YYYY: `15/03/2024` (confidence: 0.95)
- Month DD, YYYY: `June 3, 2023` (confidence: 0.95)
- Year only: `2020` (confidence: 0.5 - low due to ambiguity)

### Phase 6: Deduplication & Conflict Resolution (1 day)

**Logic**:
1. Group entities by text content (case-insensitive)
2. For duplicates: keep entity with highest confidence
3. For overlapping positions: prefer longer match
4. Merge position arrays for same entity appearing multiple times

### Phase 7: UI Integration (1 day)

**Updates Required**:
- `AnonymizationEngine.swift`: Add detection mode enum and switching logic
- `AnonymizationView.swift`: Add mode picker UI
- `SetupManager.swift`: Track selected detection mode

**Detection Modes**:
1. **AI Model** - Existing Ollama-based detection
2. **Pattern Detection (Fast)** - Swift NER only, no LLM
3. **Hybrid (AI + Patterns)** - Run both, merge results

### Phase 8: Testing & Refinement (1-2 days)

**Test Cases**:
1. Māori names in various contexts
2. Name lists ("Margaret, Brenda, and Natasha")
3. Relationship patterns ("sister Margaret")
4. NZ phone numbers and addresses
5. NHI numbers and medical IDs
6. Edge cases (punctuation, capitalization)

### Phase 9 (Optional): Custom Create ML Model (2-3 days)

**Only needed if**: Apple NER + patterns miss too many names in testing

**Process**:
1. Label 100-500 examples of clinical notes
2. Train model with Create ML
3. Bundle .mlmodel with app
4. Create CustomMLRecognizer to use model

**When to do this**: After Phase 8 testing reveals gaps

## Entity Recognizer Protocol

```swift
protocol EntityRecognizer {
    func recognize(in text: String) -> [Entity]
}
```

All recognizers implement this simple interface.

## Confidence Scoring Guidelines

- **0.95+**: Pattern match with high specificity (phone numbers, exact dictionary matches)
- **0.85-0.95**: Pattern match with good specificity (NHI numbers, known surnames)
- **0.70-0.85**: Apple NER baseline, common patterns
- **0.60-0.70**: Phonetic patterns, lower specificity
- **0.50-0.60**: Ambiguous patterns (year-only dates)

## Detection Mode Comparison

| Feature | AI Model | Pattern Detection | Hybrid |
|---------|----------|------------------|--------|
| Speed | Slow (30-90s) | Fast (<1s) | Slow (30-90s) |
| Accuracy | High | Good | Best |
| Offline | Requires Ollama | Yes | Requires Ollama |
| Hallucination Risk | Yes | No | Reduced |
| Context Awareness | Yes | No | Yes |
| NZ Patterns | Depends on model | Excellent | Excellent |

## Use Case Recommendations

**Pattern Detection (Fast)**:
- Quick anonymization of straightforward text
- Batch processing many documents
- Users without Ollama installed

**AI Model**:
- Complex contextual analysis needed
- Unusual name formats
- High accuracy critical

**Hybrid (Recommended)**:
- Best of both worlds
- AI catches contextual PII
- Patterns catch structured PII (phones, IDs)
- Cross-validation (both find it = highest confidence)

## File Structure

```
ClinicalAnon/
├── Services/
│   ├── OllamaService.swift (existing)
│   ├── AnonymizationEngine.swift (update)
│   ├── SwiftNERService.swift (new)
│   ├── EntityRecognizer.swift (new)
│   └── Recognizers/
│       ├── AppleNERRecognizer.swift (new)
│       ├── PatternRecognizer.swift (new)
│       ├── MaoriNameRecognizer.swift (new)
│       ├── RelationshipNameExtractor.swift (new)
│       ├── NZPhoneRecognizer.swift (new)
│       ├── NZMedicalIDRecognizer.swift (new)
│       ├── NZAddressRecognizer.swift (new)
│       └── DateRecognizer.swift (new)
├── Models/
│   └── Entity.swift (existing)
└── Views/
    └── AnonymizationView.swift (update)
```

## Māori Name Dictionary (Initial Set)

**Common First Names**:
Wiremu, Hemi, Pita, Rawiri, Mikaere, Tane, Rangi, Aroha, Kiri, Mere, Hana, Anahera, Moana, Ngaire, Whetu, Kahu, Ataahua, Hinewai, Hine, Marama

**Common Surnames/Second Names**:
Ngata, Te Ao, Tawhiri, Wairua, Takiri

**Note**: Can be expanded based on user feedback and actual clinical text patterns.

## Timeline

- **Week 1**: Phases 1-3 (Core service + Apple NER + Māori names)
- **Week 2**: Phases 4-5 (Relationship extractor + NZ patterns)
- **Week 3**: Phases 6-7 (Deduplication + UI integration)
- **Week 4**: Phase 8 (Testing & refinement)
- **Optional**: Phase 9 (Custom ML model if gaps found)

## Success Metrics

1. **Speed**: Pattern detection completes in <1 second (vs 30-90s for AI)
2. **Accuracy**: 90%+ precision and recall on test set
3. **NZ Coverage**: Successfully detects Māori names, NHI numbers, NZ phones
4. **No Hallucination**: No false positives on common words (vs AI issues)
5. **Hybrid Performance**: Hybrid mode catches everything either method finds

## Future Enhancements

1. **User-provided dictionaries**: Allow users to add organization-specific names/terms
2. **Learning from corrections**: Track user edits to improve patterns
3. **Custom ML training**: Train on user's own clinical notes
4. **Pattern export/import**: Share recognizers across installations
5. **Performance monitoring**: Track which recognizers find the most entities

## References

- Apple NaturalLanguage Framework: https://developer.apple.com/documentation/naturallanguage
- Create ML Documentation: https://developer.apple.com/documentation/createml
- NSRegularExpression: https://developer.apple.com/documentation/foundation/nsregularexpression

## Notes

- Start with Phases 1-3 to validate approach before investing in all recognizers
- Test on real clinical text early and often
- Prioritize patterns that add value beyond Apple NER (Māori names, NZ IDs)
- Keep recognizers independent and testable
- Use high confidence thresholds to avoid false positives
