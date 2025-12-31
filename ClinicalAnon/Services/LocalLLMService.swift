//
//  LocalLLMService.swift
//  Redactor
//
//  Purpose: Local LLM integration via MLX Swift for PII review
//  Organization: 3 Big Things
//

import Foundation
import AppKit
import Hub
import MLXLLM
import MLXLMCommon

// MARK: - PII Finding

struct PIIFinding {
    let text: String
    let suggestedType: EntityType
    let reason: String
    let confidence: Double
}

// MARK: - Model Info

struct LocalLLMModelInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let size: String
    let description: String
}

// MARK: - Local LLM Service

@MainActor
class LocalLLMService: ObservableObject {

    // MARK: - Singleton

    static let shared = LocalLLMService()

    // MARK: - Available Models

    static let availableModels: [LocalLLMModelInfo] = [
        LocalLLMModelInfo(
            id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            name: "Llama 3.1 8B (4-bit)",
            size: "~4.5 GB",
            description: "Best quality, recommended"
        ),
        LocalLLMModelInfo(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            name: "Llama 3.2 3B (4-bit)",
            size: "~1.8 GB",
            description: "Faster, smaller"
        ),
        LocalLLMModelInfo(
            id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            name: "Qwen 2.5 7B (4-bit)",
            size: "~4 GB",
            description: "Good alternative"
        )
    ]

    // MARK: - Published Properties

    @Published var isAvailable: Bool = false
    @Published var isModelLoaded: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0
    @Published var downloadStatus: String = ""
    @Published var selectedModelId: String {
        didSet {
            UserDefaults.standard.set(selectedModelId, forKey: SettingsKeys.localLLMModelId)
            // Unload current model when selection changes
            if isModelLoaded {
                unloadModel()
            }
        }
    }
    @Published var isProcessing: Bool = false
    @Published var lastError: String?

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var chatSession: ChatSession?
    private let defaultModelId = "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"

    // MARK: - Prompt

    private let systemInstructions = """
        You are a PII detection assistant. Follow the user's instructions exactly. Output only in the format requested.
        """

    // MARK: - Initialization

    private init() {
        selectedModelId = UserDefaults.standard.string(forKey: SettingsKeys.localLLMModelId) ?? defaultModelId
        checkAvailability()
    }

    // MARK: - Public Methods

    /// Check if MLX is available (requires Apple Silicon)
    func checkAvailability() {
        // MLX requires Apple Silicon
        #if arch(arm64)
        isAvailable = true
        print("LocalLLMService: MLX available on Apple Silicon")
        #else
        isAvailable = false
        lastError = "MLX requires Apple Silicon (M1/M2/M3/M4)"
        print("LocalLLMService: MLX not available - Intel Mac detected")
        #endif
    }

    /// Get the selected model info
    var selectedModelInfo: LocalLLMModelInfo? {
        Self.availableModels.first { $0.id == selectedModelId }
    }

    /// Check if the selected model is cached on disk (without loading it)
    /// Uses the Hub library's path calculation to find the correct cache location
    var isModelCached: Bool {
        let modelPath = cachedModelPath
        let exists = FileManager.default.fileExists(atPath: modelPath.path)
        print("LocalLLMService: Cache check - path: \(modelPath.path), exists: \(exists)")
        return exists
    }

    /// Get the path where the model would be cached
    /// Uses the same configuration as MLXLMCommon (caches directory, not documents)
    var cachedModelPath: URL {
        // MLXLMCommon uses cachesDirectory as downloadBase, not the default documentDirectory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let hub = HubApi(downloadBase: cacheDir)
        let repo = Hub.Repo(id: selectedModelId)
        return hub.localRepoLocation(repo)
    }

    /// Pre-load model in background (only if cached, won't trigger download)
    func preloadIfCached() async {
        print("LocalLLMService: Checking pre-load conditions...")
        print("  - isAvailable: \(isAvailable)")
        print("  - isModelCached: \(isModelCached)")
        print("  - isModelLoaded: \(isModelLoaded)")

        guard isAvailable else {
            print("LocalLLMService: Pre-load skipped - MLX not available")
            return
        }

        guard !isModelLoaded else {
            print("LocalLLMService: Pre-load skipped - model already loaded")
            return
        }

        guard isModelCached else {
            print("LocalLLMService: Pre-load skipped - model not cached, will download on first use")
            return
        }

        print("LocalLLMService: Starting background pre-load...")
        do {
            try await loadModel()
            print("LocalLLMService: Model pre-loaded successfully")
        } catch {
            print("LocalLLMService: Pre-load failed: \(error.localizedDescription)")
        }
    }

    /// Load the selected model (downloads if needed)
    func loadModel() async throws {
        guard isAvailable else {
            throw AppError.localLLMNotAvailable
        }

        if isModelLoaded && modelContext != nil {
            print("LocalLLMService: Model already loaded")
            return
        }

        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Preparing to download model..."
        lastError = nil

        print("LocalLLMService: Loading model: \(selectedModelId)")

        do {
            // Use the simple loadModel API from MLXLMCommon
            let context = try await MLXLMCommon.loadModel(
                id: selectedModelId
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress.fractionCompleted
                    if progress.fractionCompleted < 1.0 {
                        self?.downloadStatus = "Downloading: \(Int(progress.fractionCompleted * 100))%"
                    } else {
                        self?.downloadStatus = "Loading model..."
                    }
                }
            }

            self.modelContext = context

            // Create chat session with the model
            let generateParams = GenerateParameters(
                maxTokens: 1000,
                temperature: 0.1,
                topP: 0.9
            )

            self.chatSession = ChatSession(
                context,
                instructions: systemInstructions,
                generateParameters: generateParams
            )

            self.isModelLoaded = true
            self.isDownloading = false
            self.downloadStatus = ""
            print("LocalLLMService: Model loaded successfully")

        } catch {
            isDownloading = false
            downloadStatus = ""
            print("LocalLLMService: Failed to load model: \(error)")
            lastError = "Failed to load model: \(error.localizedDescription)"
            throw AppError.localLLMModelLoadFailed(error.localizedDescription)
        }
    }

    /// Unload the current model to free memory
    func unloadModel() {
        modelContext = nil
        chatSession = nil
        isModelLoaded = false
        print("LocalLLMService: Model unloaded")
    }

    /// Review original text for PII and return only findings not already covered by existing entities
    /// - Parameters:
    ///   - originalText: The original (unredacted) text to analyze
    ///   - existingEntities: Entities already detected by NER
    ///   - onAnalysisStarted: Optional callback invoked when model is loaded and analysis begins
    func reviewForMissedPII(
        originalText: String,
        existingEntities: [Entity],
        onAnalysisStarted: (() -> Void)? = nil
    ) async throws -> [PIIFinding] {
        guard isAvailable else {
            throw AppError.localLLMNotAvailable
        }

        // Load model if not already loaded
        if !isModelLoaded {
            try await loadModel()
        }

        // Notify caller that analysis is starting (model is now loaded)
        onAnalysisStarted?()

        guard let session = chatSession else {
            throw AppError.localLLMModelNotLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        // Detailed prompt for better name detection
        let prompt = """
            Find ALL personal names and contact information in this clinical text.

            NAMES TO LOOK FOR:
            - Uncommon or non-Western names (Māori, Pacific, Asian, European)
            - Truncated or misspelled names (e.g., "Meliss" for Melissa, "Joh" for John)
            - Common nouns used as names, especially when:
              - Capitalised mid-sentence (e.g., "spoke with Hope about...")
              - Following patterns like "with [word]", "asked [word]", "[word] said"
              - Near possessives like "[word]'s mother" or "[word]'s appointment"
            - Multi-part surnames (de Groot, van der Berg, O'Brien)
            - Names in professional signatures (e.g., "Dr. Janet Leathem")

            ALSO FIND:
            - Email addresses
            - Phone numbers
            - Physical addresses

            SKIP: drug names, medical terms, diagnoses, organization names, place names.

            OUTPUT FORMAT - one per line, pipe-separated:
            NAME|Storm|capitalised noun used as name
            NAME|Meihana|Māori name
            EMAIL|john@example.com|email address

            List each name/email/phone/address you find:

            \(originalText)
            """
        print("LocalLLMService: Starting PII review on original text, prompt length: \(prompt.count) chars")
        print("LocalLLMService: Using model: \(selectedModelId)")
        print("LocalLLMService: Existing entities to compare: \(existingEntities.count)")

        let startTime = Date()

        do {
            // Use the simple ChatSession API
            let responseText = try await session.respond(to: prompt)

            let elapsed = Date().timeIntervalSince(startTime)
            print("LocalLLMService: Got response in \(String(format: "%.1f", elapsed))s, length: \(responseText.count) chars")
            print("LocalLLMService: Response: \(responseText)")

            let allFindings = parseFindings(response: responseText)
            print("LocalLLMService: Parsed \(allFindings.count) total findings")

            // Filter to only findings not already covered by existing entities (delta)
            let deltaFindings = filterToDeltas(allFindings, existingEntities: existingEntities, in: originalText)
            print("LocalLLMService: Delta findings (new): \(deltaFindings.count)")

            return deltaFindings

        } catch {
            print("LocalLLMService: Generation failed: \(error)")
            throw AppError.localLLMGenerationFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    /// Parse LLM response into structured findings (handles both pipe and markdown formats)
    private func parseFindings(response: String) -> [PIIFinding] {
        var findings: [PIIFinding] = []
        var currentType: String? = nil

        let lines = response.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines or "no issues" response
            if trimmed.isEmpty || trimmed.uppercased().contains("NO_ISSUES_FOUND") {
                continue
            }

            // Try pipe format first: TYPE|text|reason
            let pipeParts = trimmed.components(separatedBy: "|")
            if pipeParts.count >= 2 {
                let typeStr = pipeParts[0].trimmingCharacters(in: .whitespaces).uppercased()
                let text = pipeParts[1].trimmingCharacters(in: .whitespaces)
                let reason = pipeParts.count > 2 ? pipeParts[2].trimmingCharacters(in: .whitespaces) : "Potential PII detected"

                if text.count > 1 && !containsPlaceholder(text) {
                    // Skip if type maps to nil (e.g., TITLE)
                    if let entityType = mapTypeToEntityType(typeStr) {
                        findings.append(PIIFinding(
                            text: text,
                            suggestedType: entityType,
                            reason: reason,
                            confidence: 0.8
                        ))
                    }
                }
                continue
            }

            // Detect section headers like "**Names**:" or "1. **Names**:"
            if let typeMatch = extractSectionType(from: trimmed) {
                currentType = typeMatch
                continue
            }

            // Parse bullet items like "- Hayden (patient)" or "- sean@email.com"
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("•") {
                if let finding = parseBulletItem(trimmed, currentType: currentType) {
                    findings.append(finding)
                }
            }
        }

        return filterValidFindings(findings)
    }

    /// Check if text contains an existing placeholder (anything in square brackets)
    private func containsPlaceholder(_ text: String) -> Bool {
        // Skip any text that contains [something]
        let regex = try? NSRegularExpression(pattern: "\\[[^\\]]+\\]", options: [])
        let range = NSRange(text.startIndex..., in: text)
        return regex?.firstMatch(in: text, options: [], range: range) != nil
    }

    /// Extract section type from headers like "**Names**:" or "1. **Names**:"
    private func extractSectionType(from line: String) -> String? {
        let patterns: [(String, String)] = [
            ("name", "NAME"), ("email", "EMAIL"), ("phone", "PHONE"),
            ("location", "LOCATION"), ("date", "DATE"), ("organization", "OTHER"),
            ("address", "LOCATION"), ("medical", "OTHER")
        ]
        let lower = line.lowercased()
        for (key, type) in patterns {
            if lower.contains(key) { return type }
        }
        return nil
    }

    /// Parse a bullet item like "- Hayden (patient)" into a PIIFinding
    private func parseBulletItem(_ line: String, currentType: String?) -> PIIFinding? {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("-") || text.hasPrefix("•") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Skip any line containing a placeholder - these are already redacted
        if containsPlaceholder(text) { return nil }

        // Extract text before parenthetical description
        var piiText = text
        var reason = "Detected by LLM"

        if let parenRange = text.range(of: " (") {
            piiText = String(text[..<parenRange.lowerBound])
            let afterParen = text[parenRange.upperBound...]
            if let closeRange = afterParen.range(of: ")") {
                reason = String(afterParen[..<closeRange.lowerBound])
            }
        }

        // Skip placeholders, short text, and text with underscores
        guard piiText.count > 1,
              !piiText.hasPrefix("["),
              !piiText.contains("_") else { return nil }

        // Skip if type maps to nil (e.g., TITLE)
        guard let entityType = mapTypeToEntityType(currentType ?? inferType(from: piiText)) else {
            return nil
        }

        return PIIFinding(
            text: piiText,
            suggestedType: entityType,
            reason: reason,
            confidence: 0.8
        )
    }

    /// Infer type from content
    private func inferType(from text: String) -> String {
        if text.contains("@") { return "EMAIL" }
        if text.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " || $0 == "(" || $0 == ")" }) { return "PHONE" }
        return "NAME"
    }

    /// Filter out duplicates and invalid findings
    private func filterValidFindings(_ findings: [PIIFinding]) -> [PIIFinding] {
        var seen = Set<String>()
        return findings.filter { finding in
            let key = finding.text.lowercased()
            guard !seen.contains(key),
                  !finding.text.hasPrefix("["),
                  finding.text.count > 1 else { return false }
            seen.insert(key)
            return true
        }
    }

    /// Map string type to EntityType (returns nil for types to skip)
    private func mapTypeToEntityType(_ typeStr: String) -> EntityType? {
        switch typeStr {
        case "NAME", "PERSON", "RELATIONSHIP":
            return .personOther
        case "EMAIL", "PHONE", "PHONE_NUMBER", "CONTACT":
            return .contact
        case "LOCATION", "ADDRESS":
            return .location
        case "DATE":
            return .date
        case "ID", "IDENTIFIER":
            return .identifier
        case "ORGANIZATION", "ORG":
            return .organization
        case "TITLE":
            // Skip job titles - not PII
            return nil
        default:
            return .personOther
        }
    }

    // MARK: - Delta Detection (Span Overlap)

    /// Filter findings to only those not already covered by existing entities
    /// Uses span/position overlap to handle edge cases like "Bob" vs "Bob's"
    private func filterToDeltas(
        _ findings: [PIIFinding],
        existingEntities: [Entity],
        in text: String
    ) -> [PIIFinding] {
        return findings.filter { finding in
            // Find all occurrences of this finding in the text
            let positions = findAllOccurrences(of: finding.text, in: text)

            guard !positions.isEmpty else {
                print("LocalLLMService: Finding '\(finding.text)' not found in text, skipping")
                return false
            }

            // Check if ANY occurrence is not covered by existing entities
            let hasUncoveredOccurrence = positions.contains { position in
                !isPositionCovered(position, by: existingEntities)
            }

            if hasUncoveredOccurrence {
                print("LocalLLMService: Delta found - '\(finding.text)' has uncovered occurrence")
            } else {
                print("LocalLLMService: '\(finding.text)' already covered by NER")
            }

            return hasUncoveredOccurrence
        }
    }

    /// Check if a position is covered by any existing entity (>50% overlap)
    private func isPositionCovered(_ position: [Int], by entities: [Entity], threshold: Double = 0.5) -> Bool {
        for entity in entities {
            for entityPos in entity.positions {
                if overlapRatio(span1: position, span2: entityPos) > threshold {
                    return true
                }
            }
        }
        return false
    }

    /// Calculate overlap ratio between two spans
    /// Returns intersection / min(length1, length2)
    private func overlapRatio(span1: [Int], span2: [Int]) -> Double {
        guard span1.count >= 2, span2.count >= 2 else { return 0 }

        let start1 = span1[0], end1 = span1[1]
        let start2 = span2[0], end2 = span2[1]

        let overlapStart = max(start1, start2)
        let overlapEnd = min(end1, end2)
        let intersection = max(0, overlapEnd - overlapStart)

        let minLength = min(end1 - start1, end2 - start2)
        guard minLength > 0 else { return 0 }

        return Double(intersection) / Double(minLength)
    }

    /// Find all occurrences of a string in text, returning positions as [[start, end], ...]
    private func findAllOccurrences(of searchText: String, in text: String) -> [[Int]] {
        // Normalize apostrophes for matching
        let normalizedSearch = searchText
            .replacingOccurrences(of: "'", with: "'")
            .replacingOccurrences(of: "'", with: "'")
        let normalizedText = text
            .replacingOccurrences(of: "'", with: "'")
            .replacingOccurrences(of: "'", with: "'")

        var positions: [[Int]] = []
        var searchStartIndex = normalizedText.startIndex

        while searchStartIndex < normalizedText.endIndex {
            if let range = normalizedText.range(
                of: normalizedSearch,
                options: .caseInsensitive,
                range: searchStartIndex..<normalizedText.endIndex
            ) {
                let start = normalizedText.distance(from: normalizedText.startIndex, to: range.lowerBound)
                let end = normalizedText.distance(from: normalizedText.startIndex, to: range.upperBound)
                positions.append([start, end])
                searchStartIndex = range.upperBound
            } else {
                break
            }
        }

        return positions
    }
}
