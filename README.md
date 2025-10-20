# ClinicalAnon

**Privacy-first clinical text anonymization for macOS**

![Status](https://img.shields.io/badge/status-in%20development-orange)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.9%2B-orange)

---

## Overview

ClinicalAnon is a macOS-native application designed for psychology and wellbeing practitioners to anonymize clinical notes before sharing for case discussions, supervision, or research purposes.

### Core Principles

- **100% local processing** - No cloud uploads, no internet required after setup
- **AI-assisted with human oversight** - LLM detects entities, practitioner reviews before applying
- **Clinical context preserved** - Replaces identifying information while maintaining therapeutic meaning
- **Privacy-first** - All processing in-memory only, nothing ever written to disk
- **New Zealand cultural competence** - Handles te reo Māori names and NZ-specific contexts appropriately

---

## Features

- ✅ **Two-pane interface** - Original text on left, anonymized version on right
- ✅ **Entity highlighting** - Visual feedback on detected/replaced entities
- ✅ **Consistent mapping** - Same entity always gets same code within session
- ✅ **Editable output** - Practitioner can refine AI suggestions
- ✅ **Local AI** - Uses Ollama with Llama 3.1 8B model (runs on your Mac)
- ✅ **Zero persistence** - No files created, no data saved, complete privacy

### Entity Types Detected

- **Clients/Patients** → `[CLIENT_A]`, `[CLIENT_B]`, etc.
- **Healthcare Providers** → `[PROVIDER_A]`, `[PROVIDER_B]`, etc.
- **Locations** → `[LOCATION_A]`, `[LOCATION_B]`, etc.
- **Organizations** → `[ORGANIZATION_A]`, `[ORGANIZATION_B]`, etc.
- **Dates** → `[DATE_A]`, `[DATE_B]`, etc.
- **Identifiers** → `[ID_A]`, `[ID_B]`, etc. (NHI, phone, email)

### What's Preserved

- Age and gender
- Diagnoses and symptoms
- Treatment approaches
- Relative timeframes ("early 2024", "6 months ago")
- General locations ("at home", "workplace")
- Clinical meaning and context

---

## Technology Stack

- **Platform:** macOS 13 (Ventura) or later
- **Framework:** SwiftUI (native macOS)
- **Language:** Swift 5.9+
- **Architecture:** Apple Silicon primary, Intel compatible
- **AI Engine:** Ollama with Llama 3.1 8B (installed separately)
- **Dependencies:** None (pure Swift/SwiftUI)

---

## Project Status

**Current Phase:** Planning & Setup (Phase 1 of 10)

### Development Phases

1. ✅ **Planning** - Complete specification and implementation plan
2. ⏳ **Phase 1:** Project Setup & Design System
3. 🔲 **Phase 2:** Setup Flow & Ollama Integration
4. 🔲 **Phase 3:** Core Data Models
5. 🔲 **Phase 4:** Business Logic - Services
6. 🔲 **Phase 5:** UI Components
7. 🔲 **Phase 6:** Main App View
8. 🔲 **Phase 7:** Real Ollama Integration
9. 🔲 **Phase 8:** Polish & Edge Cases
10. 🔲 **Phase 9:** Testing & Validation
11. 🔲 **Phase 10:** Deployment Preparation

---

## Documentation

- **[Complete Specification](ClinicalAnon-Complete-Specification.md)** - Comprehensive product spec (140KB)
- **[Implementation Plan](docs/Implementation-Plan.md)** - Phase-by-phase development plan
- **[Phase Documents Checklist](docs/Phase-Documents-Checklist.md)** - All files to create
- **[Claude Context](.claude.md)** - Project context for AI-assisted development

---

## Architecture

### Design Pattern
- **MVVM** (Model-View-ViewModel)
- **Protocol-oriented** with dependency injection
- **Swift Concurrency** (async/await)

### Privacy Model
- **In-memory only** - No file system writes
- **Session-scoped** - Entity mappings reset on clear/quit
- **No telemetry** - No tracking, no analytics, no cloud

### File Structure
```
ClinicalAnon/
├── ClinicalAnonApp.swift       # App entry point
├── Views/                      # SwiftUI views
│   ├── ContentView.swift       # Main two-pane interface
│   ├── SetupView.swift         # Setup wizard
│   └── Components/             # Reusable UI components
├── ViewModels/                 # App state & logic
│   └── AppViewModel.swift
├── Models/                     # Data structures
│   ├── Entity.swift
│   ├── EntityType.swift
│   └── AnalysisResult.swift
├── Services/                   # Business logic
│   ├── OllamaService.swift     # LLM communication
│   ├── EntityMapper.swift      # Consistency tracking
│   └── AnonymizationEngine.swift
└── Utilities/                  # Helpers
    ├── DesignSystem.swift      # Brand colors & typography
    ├── AppError.swift          # Error handling
    └── SetupManager.swift      # Ollama detection
```

---

## Design System

### Brand Colors
- **Primary Teal** `#0A6B7C` - Professional, trustworthy
- **Sage** `#A9C1B5` - Calm, clinical
- **Orange** `#E68A2E` - Energy, action
- **Sand** `#E8D4BC` / `#D4AE80` - Warmth
- **Charcoal** `#2E2E2E` - Text, contrast
- **Warm White** `#FAF7F4` - Backgrounds

### Typography
- **Headings:** Lora (serif) - Warm, professional
- **Body:** Source Sans 3 (sans-serif) - Clean, readable
- **Monospace:** SF Mono (system) - Clinical notes

---

## Development Setup

### Prerequisites
- Xcode 15 or later
- macOS 13 (Ventura) or later
- Git

### For Testing (Optional)
- Homebrew
- Ollama (`brew install ollama`)
- Llama 3.1 8B model (`ollama pull llama3.1:8b`)

### Getting Started

```bash
# Clone repository
git clone https://github.com/yourusername/clinicalanon.git
cd clinicalanon

# Open in Xcode
open ClinicalAnon/ClinicalAnon.xcodeproj

# Build and run
# Xcode will handle dependencies
```

---

## Contributing

This project is currently in active development. Contribution guidelines will be added once the MVP is complete.

---

## Privacy & Security

### Data Handling
- **No cloud processing** - Everything runs locally
- **No file writes** - All processing in RAM
- **No logs** - No debugging logs with sensitive data
- **No analytics** - No telemetry or usage tracking
- **No network** - After initial setup, no internet required

### Security Model
- **User data stays local** - Never leaves the device
- **LLM runs locally** - Ollama processes text on-device
- **Session-only memory** - Cleared on app quit
- **Direct download** - No App Store approval delays for security patches

---

## License

*License to be determined*

---

## Organization

**3 Big Things**

Psychology and wellbeing practitioners creating tools for clinical practice.

---

## Acknowledgments

- Built with Swift and SwiftUI
- AI processing via Ollama and Llama 3.1
- Design inspired by clinical practice needs
- Te reo Māori support for Aotearoa New Zealand context

---

**Note:** This project is in active development. The application is not yet ready for production use.

---

*Last updated: October 2025*
