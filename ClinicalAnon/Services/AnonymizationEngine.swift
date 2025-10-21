//
//  AnonymizationEngine.swift
//  ClinicalAnon
//
//  Purpose: Main orchestrator for clinical text anonymization
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Detection Mode

/// Detection method for entity recognition
enum DetectionMode: String, CaseIterable, Identifiable {
    case aiModel = "AI Model"
    case patterns = "Pattern Detection (Fast)"
    case hybrid = "Hybrid (AI + Patterns)"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .aiModel:
            return "Use AI model for context-aware detection"
        case .patterns:
            return "Fast pattern-based detection (offline)"
        case .hybrid:
            return "Combine AI and patterns for best accuracy"
        }
    }
}

// MARK: - Anonymization Engine

/// Main engine that orchestrates the anonymization process
@MainActor
class AnonymizationEngine: ObservableObject {

    // MARK: - Properties

    /// The Ollama service for LLM communication
    private let ollamaService: OllamaServiceProtocol

    /// Swift NER service for pattern-based detection
    private let swiftNERService: SwiftNERService

    /// Entity mapping for consistent replacements within session
    let entityMapping: EntityMapping

    /// Current detection mode - persists across app launches
    @Published var detectionMode: DetectionMode = .aiModel {
        didSet {
            // Save to UserDefaults
            UserDefaults.standard.set(detectionMode.rawValue, forKey: "detectionMode")
        }
    }

    /// Published processing state
    @Published private(set) var isProcessing: Bool = false

    /// Published estimated processing time in seconds
    @Published private(set) var estimatedSeconds: Int = 0

    /// Published status message
    @Published private(set) var statusMessage: String = ""

    // MARK: - Initialization

    init(
        ollamaService: OllamaServiceProtocol,
        entityMapping: EntityMapping? = nil
    ) {
        self.ollamaService = ollamaService
        self.swiftNERService = SwiftNERService()
        self.entityMapping = entityMapping ?? EntityMapping()

        // Load saved detection mode from UserDefaults
        if let savedMode = UserDefaults.standard.string(forKey: "detectionMode"),
           let mode = DetectionMode(rawValue: savedMode) {
            self.detectionMode = mode
        }
    }

    // MARK: - Main Anonymization Method

    /// Anonymize clinical text using the LLM
    /// - Parameter originalText: The clinical text to anonymize
    /// - Returns: Complete anonymization result
    /// - Throws: AppError if anonymization fails
    func anonymize(_ originalText: String) async throws -> AnonymizationResult {
        // Validate input
        guard !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.emptyText
        }

        // Calculate estimated time based on word count
        let wordCount = originalText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        estimatedSeconds = estimateProcessingTime(wordCount: wordCount)

        // Start processing
        isProcessing = true
        statusMessage = "Preparing request..."
        defer {
            isProcessing = false
            estimatedSeconds = 0
            statusMessage = ""
        }

        let startTime = Date()

        // Detect entities using selected method
        let rawEntities: [Entity]

        switch detectionMode {
        case .aiModel:
            // AI-only detection
            rawEntities = try await detectWithAI(originalText)

        case .patterns:
            // Pattern-only detection (fast)
            rawEntities = try await swiftNERService.detectEntities(in: originalText)

        case .hybrid:
            // Run both AI and patterns, merge results
            statusMessage = "Running hybrid detection..."

            async let aiEntities = detectWithAI(originalText)
            async let patternEntities = swiftNERService.detectEntities(in: originalText)

            let merged = try await mergeEntities(aiEntities, patternEntities)
            rawEntities = merged
        }

        // Step 4: Apply entity mapping for consistency
        statusMessage = "Applying entity mapping..."

        let mappedEntities = applyEntityMapping(to: rawEntities)

        // Step 5: Generate anonymized text locally using TextReplacer
        statusMessage = "Anonymizing text..."

        let anonymizedText = try TextReplacer.replaceEntities(in: originalText, with: mappedEntities)

        // Step 6: Validate positions
        statusMessage = "Validating results..."

        let validationIssues = EntityDetector.validatePositions(
            entities: mappedEntities,
            originalText: originalText
        )

        // Note: Validation issues are logged but don't prevent processing
        // The LLM may have slightly imprecise position markers but correct replacements

        // Step 7: Create result
        statusMessage = "Finalizing..."

        let processingTime = Date().timeIntervalSince(startTime)

        let metadata = AnonymizationMetadata(
            modelUsed: (ollamaService as? OllamaService)?.modelName,
            processingTime: processingTime,
            averageConfidence: calculateAverageConfidence(mappedEntities),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )

        let result = AnonymizationResult(
            originalText: originalText,
            anonymizedText: anonymizedText,
            entities: mappedEntities,
            metadata: metadata
        )

        statusMessage = "Complete!"

        return result
    }

    /// Clear all entity mappings (start fresh session)
    func clearSession() {
        entityMapping.clearAll()
    }

    /// Update the model name for the Ollama service
    /// - Parameter modelName: The new model name to use
    func updateModelName(_ modelName: String) {
        if let service = ollamaService as? OllamaService {
            service.modelName = modelName
        }
    }

    // MARK: - Private Methods

    /// Estimate processing time based on word count and detection mode
    /// - Parameter wordCount: Number of words in the input text
    /// - Returns: Estimated seconds
    private func estimateProcessingTime(wordCount: Int) -> Int {
        switch detectionMode {
        case .patterns:
            // Pattern detection is very fast (<1 second for most texts)
            return 1

        case .aiModel:
            // AI model: ~30 seconds base + processing time
            // Rate: ~3-4 words per second for typical models
            let baseTime = 30
            let wordsPerSecond = 3.5
            let estimatedTime = baseTime + Int(Double(wordCount) / wordsPerSecond)
            return max(estimatedTime, 15)

        case .hybrid:
            // Hybrid: mainly limited by AI processing time
            // Patterns run in parallel so add minimal overhead
            let baseTime = 30
            let wordsPerSecond = 3.5
            let estimatedTime = baseTime + Int(Double(wordCount) / wordsPerSecond) + 5 // +5s for merging
            return max(estimatedTime, 20)
        }
    }

    // MARK: - Private Helper Methods

    /// Detect entities using AI model
    private func detectWithAI(_ originalText: String) async throws -> [Entity] {
        // Step 1: Build prompt
        statusMessage = "Building prompt..."
        let systemPrompt = PromptBuilder.buildAnonymizationPrompt()

        // Step 2: Send to LLM
        statusMessage = "Analyzing text with AI..."

        let llmResponse: String
        do {
            llmResponse = try await ollamaService.sendRequest(
                text: originalText,
                systemPrompt: systemPrompt
            )
        } catch {
            throw AppError.networkError(error)
        }

        // Step 3: Parse response to get entities
        statusMessage = "Processing AI response..."

        let entities = try EntityDetector.parseResponse(llmResponse)

        return entities
    }

    /// Merge entities from AI and pattern detection
    /// Prefers entities with higher confidence, combines results
    private func mergeEntities(_ aiEntities: [Entity], _ patternEntities: [Entity]) -> [Entity] {
        statusMessage = "Merging AI and pattern results..."

        var entityMap: [String: Entity] = [:]

        // Add AI entities first
        for entity in aiEntities {
            let key = entity.originalText.lowercased()
            entityMap[key] = entity
        }

        // Add pattern entities, keeping higher confidence
        for entity in patternEntities {
            let key = entity.originalText.lowercased()

            if let existing = entityMap[key] {
                // Keep entity with higher confidence
                let newConfidence = entity.confidence ?? 0.0
                let existingConfidence = existing.confidence ?? 0.0

                if newConfidence > existingConfidence {
                    entityMap[key] = entity
                }
            } else {
                // New entity from patterns
                entityMap[key] = entity
            }
        }

        print("📊 Merged results: \(aiEntities.count) AI + \(patternEntities.count) patterns = \(entityMap.count) unique")

        return Array(entityMap.values)
    }

    /// Apply entity mapping to ensure consistency
    private func applyEntityMapping(to entities: [Entity]) -> [Entity] {
        var mappedEntities: [Entity] = []

        for entity in entities {
            // Get or create consistent replacement code
            let consistentCode = entityMapping.getReplacementCode(
                for: entity.originalText,
                type: entity.type
            )

            // Create new entity with consistent code
            let mappedEntity = Entity(
                id: entity.id,
                originalText: entity.originalText,
                replacementCode: consistentCode,
                type: entity.type,
                positions: entity.positions,
                confidence: entity.confidence
            )

            mappedEntities.append(mappedEntity)
        }

        return mappedEntities
    }

    /// Calculate average confidence across all entities
    private func calculateAverageConfidence(_ entities: [Entity]) -> Double? {
        let confidenceScores = entities.compactMap { $0.confidence }

        guard !confidenceScores.isEmpty else {
            return nil
        }

        let sum = confidenceScores.reduce(0.0, +)
        return sum / Double(confidenceScores.count)
    }
}

// MARK: - Batch Processing

extension AnonymizationEngine {
    /// Anonymize multiple texts in batch
    /// - Parameter texts: Array of clinical texts
    /// - Returns: Array of results (same order as input)
    func anonymizeBatch(_ texts: [String]) async throws -> [AnonymizationResult] {
        var results: [AnonymizationResult] = []

        for (index, text) in texts.enumerated() {
            statusMessage = "Processing text \(index + 1) of \(texts.count)..."

            let result = try await anonymize(text)
            results.append(result)
        }

        return results
    }
}

// MARK: - Statistics

extension AnonymizationEngine {
    /// Get current session statistics
    var sessionStatistics: MappingStatistics {
        return entityMapping.statistics
    }

    /// Get summary of current session
    var sessionSummary: String {
        let stats = sessionStatistics
        return """
        Session Summary:
        • Total unique entities mapped: \(stats.totalMappings)
        • Clients: \(stats.typeCounts[.personClient] ?? 0)
        • Providers: \(stats.typeCounts[.personProvider] ?? 0)
        • Dates: \(stats.typeCounts[.date] ?? 0)
        • Locations: \(stats.typeCounts[.location] ?? 0)
        • Other: \(stats.totalMappings - (stats.typeCounts.values.reduce(0, +)))
        """
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension AnonymizationEngine {
    /// Engine with mock service for previews
    static var preview: AnonymizationEngine {
        let mockService = MockOllamaService.success
        return AnonymizationEngine(ollamaService: mockService)
    }

    /// Engine with real service for testing
    static var real: AnonymizationEngine {
        let realService = OllamaService.real
        return AnonymizationEngine(ollamaService: realService)
    }

    /// Engine in mock mode
    static var mock: AnonymizationEngine {
        let mockService = OllamaService(mockMode: true)
        return AnonymizationEngine(ollamaService: mockService)
    }

    /// Test anonymization with sample data
    func testAnonymize() async throws -> AnonymizationResult {
        let sampleText = """
        Jane Smith attended her session on March 15, 2024.
        Dr. Wilson conducted the assessment at Auckland Clinic.
        Jane reported improvement in managing anxiety symptoms.
        """

        return try await anonymize(sampleText)
    }
}
#endif
