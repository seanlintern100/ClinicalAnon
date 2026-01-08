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

    /// Callback for download progress updates (used by UI to track downloads)
    var onDownloadProgress: ((Double, String) -> Void)?

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var chatSession: ChatSession?
    private let defaultModelId = "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"

    // MARK: - Prompt

    private let systemInstructions = """
        You are a PII extraction assistant. Copy text exactly as it appears. Output only in pipe format, no markdown.
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
    /// Checks for actual model weight files, not just an empty directory
    var isModelCached: Bool {
        let modelPath = cachedModelPath
        let hasWeights = hasModelWeights(at: modelPath)
        print("LocalLLMService: Cache check - path: \(modelPath.path), hasWeights: \(hasWeights)")
        return hasWeights
    }

    /// Get the path where the model would be cached
    /// MLX caches models at ~/Library/Caches/models/{modelId}
    var cachedModelPath: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("models").appendingPathComponent(selectedModelId)
    }

    /// Check if the model has actual weight files (not just an empty directory)
    private func hasModelWeights(at path: URL) -> Bool {
        // Check for .safetensors files which indicate actual model weights
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path.path) else { return false }
        return contents.contains { $0.hasSuffix(".safetensors") || $0 == "config.json" }
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
                    let status: String
                    if progress.fractionCompleted < 1.0 {
                        status = "Downloading model... \(Int(progress.fractionCompleted * 100))%"
                    } else {
                        status = "Loading model..."
                    }
                    self?.downloadStatus = status

                    // Notify external callback (for UI tracking)
                    self?.onDownloadProgress?(progress.fractionCompleted, status)
                }
            }

            self.modelContext = context

            // Create chat session with the model
            let generateParams = GenerateParameters(
                maxTokens: 1000,
                temperature: 0.1,
                topP: 0.9,
                repetitionPenalty: 1.1  // Lowered from 1.2 to avoid suppressing repeated NAME| format
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

    /// Delete the cached model files from disk
    func deleteModel() {
        // First unload from memory
        unloadModel()

        // Delete cached files
        let path = cachedModelPath
        do {
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
                print("LocalLLMService: Model deleted from \(path.path)")
            }
        } catch {
            print("LocalLLMService: Failed to delete model: \(error)")
            lastError = "Failed to delete model: \(error.localizedDescription)"
        }
    }

    // MARK: - Chunking Configuration

    /// Maximum text length before chunking is applied
    private let chunkingThreshold = 8_000

    /// Chunk size for processing (conservative for 8B model)
    private let chunkSize = 6_000

    /// Overlap between chunks to catch names at boundaries
    private let chunkOverlap = 200

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

        guard chatSession != nil else {
            throw AppError.localLLMModelNotLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        print("LocalLLMService: Starting PII review, text length: \(originalText.count) chars")
        print("LocalLLMService: Using model: \(selectedModelId)")
        print("LocalLLMService: Existing entities to compare: \(existingEntities.count)")

        let startTime = Date()
        var allFindings: [PIIFinding] = []

        // Use chunking for long texts to avoid overwhelming the model
        if originalText.count > chunkingThreshold {
            let chunks = ChunkManager.splitWithOverlap(
                originalText,
                chunkSize: chunkSize,
                overlap: chunkOverlap
            )
            print("LocalLLMService: Text exceeds \(chunkingThreshold) chars, split into \(chunks.count) chunks")

            for (index, chunk) in chunks.enumerated() {
                print("LocalLLMService: Processing chunk \(index + 1)/\(chunks.count) (\(chunk.text.count) chars)")

                do {
                    let chunkFindings = try await reviewSingleChunk(chunk.text)
                    print("LocalLLMService: Chunk \(index + 1) found \(chunkFindings.count) findings")
                    allFindings.append(contentsOf: chunkFindings)
                } catch {
                    print("LocalLLMService: Chunk \(index + 1) failed: \(error.localizedDescription)")
                    // Continue with other chunks even if one fails
                }
            }
        } else {
            // Short text - process in single call
            allFindings = try await reviewSingleChunk(originalText)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("LocalLLMService: Total processing time: \(String(format: "%.1f", elapsed))s")
        print("LocalLLMService: Total findings before dedup: \(allFindings.count)")

        // Filter to only findings not already covered by existing entities (delta)
        let deltaFindings = filterToDeltas(allFindings, existingEntities: existingEntities, in: originalText)
        print("LocalLLMService: Delta findings (new): \(deltaFindings.count)")

        return deltaFindings
    }

    /// Process a single chunk of text for PII
    private func reviewSingleChunk(_ text: String) async throws -> [PIIFinding] {
        guard let context = modelContext else {
            throw AppError.localLLMModelNotLoaded
        }

        // Create fresh session for this chunk (avoids context accumulation across chunks)
        let generateParams = GenerateParameters(
            maxTokens: 1000,
            temperature: 0.1,
            topP: 0.9,
            repetitionPenalty: 1.1
        )
        let session = ChatSession(context, instructions: systemInstructions, generateParameters: generateParams)

        // Detailed prompt for better name detection
        let prompt = """
            Extract personal names and contact information from this clinical text.

            CRITICAL RULES:
            1. Copy text EXACTLY as it appears - do not paraphrase or summarize
            2. Output ONLY in pipe format below - no markdown, no bullets, no headers
            3. One finding per line, nothing else
            4. Do NOT summarize or describe the content

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
            - Phone numbers (any format)
            - Physical/street addresses

            SKIP:
            - Drug names, medical terms, diagnoses
            - Organization names, place names, suburbs, cities
            - Document names (e.g., "Protection Order", "Lawyer for Child report")
            - Role descriptions without names (e.g., "the psychologist", "client's mother")

            OUTPUT FORMAT - exactly like this, no other text:
            NAME|Storm|noun used as name
            NAME|Meihana|Māori name
            PHONE|021 123 4567|phone number
            EMAIL|john@example.com|email

            If nothing found, output only: NO_ISSUES_FOUND

            Extract from this section (may be part of a larger document):

            \(text)
            """

        let responseText = try await session.respond(to: prompt)
        print("LocalLLMService: Response length: \(responseText.count) chars")

        // Check if response looks like a summary instead of findings
        if responseText.count > 200 && !responseText.contains("|") && !responseText.uppercased().contains("NO_ISSUES_FOUND") {
            print("LocalLLMService: WARNING - Response appears to be a summary, not structured findings")
            return []
        }

        let findings = parseFindings(response: responseText)
        return findings
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
                var typeStr = pipeParts[0].trimmingCharacters(in: .whitespaces).uppercased()
                var text = pipeParts[1].trimmingCharacters(in: .whitespaces)
                let reason = pipeParts.count > 2 ? pipeParts[2].trimmingCharacters(in: .whitespaces) : "Potential PII detected"

                // Handle malformed LLM output like "1. **Jo**|exact text|..."
                // Extract name from first part if it contains ** markers
                if let nameMatch = typeStr.range(of: "\\*\\*(.+?)\\*\\*", options: .regularExpression) {
                    let captured = String(typeStr[nameMatch])
                    text = captured.replacingOccurrences(of: "**", with: "")
                    typeStr = "NAME"
                }

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

    /// Common title prefixes that LLMs often add but may not be in the original text
    private let titlePrefixes = ["Dr.", "Dr ", "Mr.", "Mr ", "Mrs.", "Mrs ", "Ms.", "Ms ", "Prof.", "Prof ", "Professor "]

    /// Strip common title prefixes from a name
    private func stripTitlePrefix(_ text: String) -> String {
        var result = text
        for prefix in titlePrefixes {
            if result.lowercased().hasPrefix(prefix.lowercased()) {
                result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return result
    }

    /// Filter findings to only those not already covered by existing entities
    /// Uses span/position overlap to handle edge cases like "Bob" vs "Bob's"
    private func filterToDeltas(
        _ findings: [PIIFinding],
        existingEntities: [Entity],
        in text: String
    ) -> [PIIFinding] {
        return findings.compactMap { finding -> PIIFinding? in
            // First try exact match
            var positions = findAllOccurrences(of: finding.text, in: text)
            var searchText = finding.text

            // If not found, try stripping title prefix (e.g., "Dr. Janet Leathem" -> "Janet Leathem")
            if positions.isEmpty {
                let strippedText = stripTitlePrefix(finding.text)
                if strippedText != finding.text {
                    positions = findAllOccurrences(of: strippedText, in: text)
                    if !positions.isEmpty {
                        searchText = strippedText
                        print("LocalLLMService: Found '\(strippedText)' after stripping prefix from '\(finding.text)'")
                    }
                }
            }

            guard !positions.isEmpty else {
                print("LocalLLMService: Finding '\(finding.text)' not found in text, skipping")
                return nil
            }

            // Check if ANY occurrence is not covered by existing entities
            let hasUncoveredOccurrence = positions.contains { position in
                !isPositionCovered(position, by: existingEntities)
            }

            if hasUncoveredOccurrence {
                print("LocalLLMService: Delta found - '\(searchText)' has uncovered occurrence")
                // Return finding with the text that was actually found in the document
                return PIIFinding(
                    text: searchText,
                    suggestedType: finding.suggestedType,
                    reason: finding.reason,
                    confidence: finding.confidence
                )
            } else {
                print("LocalLLMService: '\(searchText)' already covered by NER")
                return nil
            }
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
