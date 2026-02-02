//
//  LiveRedactor.swift
//  ClinicalAnon
//
//  Purpose: Incremental entity detection during live recording sessions
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Live Redactor

/// Service for incremental entity detection during live recording
/// Runs both SwiftNER (patterns + Apple NER) and XLM-RoBERTa (CoreML NER) in parallel
@MainActor
class LiveRedactor: ObservableObject {

    // MARK: - Singleton

    static let shared = LiveRedactor()

    // MARK: - Services

    private let swiftNERService = SwiftNERService.shared
    private let xlmrService = XLMRobertaNERService.shared

    // MARK: - Published State

    @Published private(set) var isProcessing: Bool = false

    // MARK: - Private State

    /// Tracks which segment IDs have been processed per session
    private var processedSegmentIds: [UUID: Set<UUID>] = [:]

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Process new transcript segments for a session
    /// Runs BOTH SwiftNER (patterns) AND XLM-RoBERTa (CoreML) for best accuracy
    func processNewSegments(for session: LiveSession, segments: [TranscriptSegment]) async {
        guard !segments.isEmpty else { return }

        // Filter to unprocessed segments only
        let newSegments = segments.filter { !isSegmentProcessed(sessionId: session.id, segmentId: $0.id) }
        guard !newSegments.isEmpty else { return }

        isProcessing = true
        defer { isProcessing = false }

        // Build combined text for detection
        let combinedText = newSegments.map { $0.text }.joined(separator: " ")

        #if DEBUG
        print("LiveRedactor: Processing \(newSegments.count) new segments (\(combinedText.count) chars)")
        #endif

        // Run BOTH detection services in parallel
        async let patternEntities = runSwiftNER(text: combinedText)
        async let xlmrFindings = runXLMRNER(text: combinedText, existingEntities: session.detectedEntities)

        // Process pattern-based entities
        let patterns = await patternEntities
        for entity in patterns {
            addEntityToSession(entity, session: session)
        }

        // Process XLM-RoBERTa findings
        let findings = await xlmrFindings
        for finding in findings {
            let entity = Entity(
                originalText: finding.text,
                replacementCode: "",
                type: finding.suggestedType,
                positions: [],
                confidence: finding.confidence
            )
            addEntityToSession(entity, session: session)
        }

        // Mark segments as processed
        markSegmentsProcessed(sessionId: session.id, segmentIds: newSegments.map { $0.id })

        #if DEBUG
        print("LiveRedactor: Session now has \(session.detectedEntities.count) entities")
        #endif
    }

    /// Clear tracking data for a session
    func clearSession(_ sessionId: UUID) {
        processedSegmentIds.removeValue(forKey: sessionId)
        #if DEBUG
        print("LiveRedactor: Cleared session \(sessionId)")
        #endif
    }

    /// Check if a segment has been processed
    func isSegmentProcessed(sessionId: UUID, segmentId: UUID) -> Bool {
        processedSegmentIds[sessionId]?.contains(segmentId) ?? false
    }

    // MARK: - Private Methods

    /// Run SwiftNER detection (patterns + Apple NER)
    private func runSwiftNER(text: String) async -> [Entity] {
        do {
            return try await swiftNERService.detectEntities(in: text)
        } catch {
            #if DEBUG
            print("LiveRedactor: SwiftNER error: \(error.localizedDescription)")
            #endif
            return []
        }
    }

    /// Run XLM-RoBERTa NER detection
    private func runXLMRNER(text: String, existingEntities: [Entity]) async -> [PIIFinding] {
        do {
            return try await xlmrService.runNERScan(text: text, existingEntities: existingEntities)
        } catch {
            #if DEBUG
            print("LiveRedactor: XLM-RoBERTa error: \(error.localizedDescription)")
            #endif
            return []
        }
    }

    /// Add entity to session with consistent code from EntityMapping
    private func addEntityToSession(_ entity: Entity, session: LiveSession) {
        let normalized = entity.originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip empty or very short entities
        guard normalized.count >= 2 else { return }

        // Skip if already detected (case-insensitive)
        guard !session.detectedEntities.contains(where: { $0.originalText.lowercased() == normalized }) else {
            return
        }

        // Register multi-word person names as anchors for better family clustering
        // This ensures "John" detected later will link to "John Smith" detected earlier
        if entity.type.isPerson {
            let words = entity.originalText.components(separatedBy: " ").filter { !$0.isEmpty }
            if words.count >= 2 {
                _ = session.entityMapping.registerPersonAnchor(
                    fullName: entity.originalText,
                    type: entity.type
                )
            }
        }

        // Get or create consistent replacement code
        let code = session.entityMapping.getReplacementCode(
            for: entity.originalText,
            type: entity.type
        )

        let mappedEntity = Entity(
            originalText: entity.originalText,
            replacementCode: code,
            type: entity.type,
            positions: entity.positions,
            confidence: entity.confidence
        )

        session.detectedEntities.append(mappedEntity)

        #if DEBUG
        print("LiveRedactor: Added entity '\(entity.originalText)' → \(code)")
        #endif
    }

    /// Mark segments as processed
    private func markSegmentsProcessed(sessionId: UUID, segmentIds: [UUID]) {
        if processedSegmentIds[sessionId] == nil {
            processedSegmentIds[sessionId] = []
        }
        processedSegmentIds[sessionId]?.formUnion(segmentIds)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension LiveRedactor {
    /// Test processing with sample text
    func testDetection(for session: LiveSession, text: String) async {
        let testSegment = TranscriptSegment(
            speaker: .clinician,
            text: text,
            startTime: 0,
            endTime: 10,
            chunkIndex: 0,
            confidence: 0.9
        )
        await processNewSegments(for: session, segments: [testSegment])
    }
}
#endif
