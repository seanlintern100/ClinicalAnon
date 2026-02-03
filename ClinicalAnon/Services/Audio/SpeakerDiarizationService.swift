//
//  SpeakerDiarizationService.swift
//  ClinicalAnon
//
//  Purpose: Speaker diarization using FluidAudio for identifying multiple remote speakers
//  Organization: 3 Big Things
//

import Foundation
import FluidAudio

// MARK: - Diarization Error

enum DiarizationError: Error, LocalizedError {
    case notInitialized
    case modelLoadFailed(String)
    case diarizationFailed(String)
    case audioFileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Speaker diarization service is not initialized."
        case .modelLoadFailed(let reason):
            return "Failed to load diarization model: \(reason)"
        case .diarizationFailed(let reason):
            return "Diarization failed: \(reason)"
        case .audioFileNotFound(let path):
            return "Audio file not found at: \(path)"
        }
    }
}

// MARK: - Speaker Segment

/// Represents a segment of audio attributed to a specific speaker
struct SpeakerSegment {
    /// Speaker identifier (e.g., "1", "2") - consistent across chunks via SpeakerManager
    let speakerId: String

    /// Start time in seconds
    let startTime: TimeInterval

    /// End time in seconds
    let endTime: TimeInterval

    /// Confidence of speaker identification (0-1)
    let confidence: Float

    /// Speaker embedding vector (256D) for cross-chunk matching
    let embedding: [Float]?

    /// Duration of this segment
    var duration: TimeInterval {
        endTime - startTime
    }

    init(speakerId: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float, embedding: [Float]? = nil) {
        self.speakerId = speakerId
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.embedding = embedding
    }
}

// MARK: - Speaker Diarization Service

/// Service for identifying and separating multiple speakers in audio
/// Uses FluidAudio's OfflineDiarizerManager (pyannote-based) for on-device diarization
/// Maintains a SpeakerManager for consistent speaker IDs across chunks
@MainActor
class SpeakerDiarizationService: ObservableObject {

    // MARK: - Singleton

    static let shared = SpeakerDiarizationService()

    // MARK: - Published State

    @Published private(set) var isInitialized: Bool = false
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var error: DiarizationError?

    // MARK: - FluidAudio Diarizer

    private var diarizer: OfflineDiarizerManager?

    // MARK: - Cross-Chunk Speaker Tracking

    /// Reference embeddings from first chunk, keyed by consistent speaker ID ("1", "2")
    /// Used to re-map subsequent chunks' speaker IDs for consistency
    private var referenceEmbeddings: [String: [Float]] = [:]

    // MARK: - Initialization

    private init() {}

    /// Initialize the diarization model
    /// Call this before first use (can be called during app startup or lazily)
    func initialize() async throws {
        guard !isInitialized else { return }

        do {
            // Use FluidAudio defaults but force exactly 2 speakers for telehealth
            // Default clusteringThreshold is 0.7 (optimal for AMI dataset at 17.7% DER)
            var config = OfflineDiarizerConfig()
            config.clustering.numSpeakers = 2  // Force exactly 2 speakers (clinician scenario)

#if DEBUG
            print("SpeakerDiarizationService: FluidAudio config - using defaults with numSpeakers=\(config.clustering.numSpeakers ?? -1)")
#endif

            diarizer = OfflineDiarizerManager(config: config)
            try await diarizer?.prepareModels()

            // Note: Cross-chunk SpeakerManager tracking disabled - was causing speaker merging issues
            // Each chunk will have independent speaker IDs (S1, S2) which may not match across chunks
            // TODO: Re-enable cross-chunk tracking once per-chunk accuracy is confirmed

            isInitialized = true
#if DEBUG
            print("SpeakerDiarizationService: FluidAudio diarizer initialized successfully")
#endif
        } catch {
            self.error = .modelLoadFailed(error.localizedDescription)
            throw DiarizationError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Unload the model to free memory
    func unload() {
        diarizer = nil
        referenceEmbeddings = [:]
        isInitialized = false
    }

    /// Reset speaker tracking for a new session
    /// Clears reference embeddings so the next chunk establishes new speaker identities
    func resetSpeakerTracking() {
        referenceEmbeddings = [:]
#if DEBUG
        print("SpeakerDiarizationService: Speaker tracking reset - reference embeddings cleared")
#endif
    }

    // MARK: - Diarization

    /// Diarize audio to identify distinct speakers
    /// Note: Speaker IDs (1, 2) are per-chunk and may not be consistent across chunks
    /// - Parameter audioURL: URL to the audio file
    /// - Returns: Array of speaker segments with timing and speaker IDs
    func diarize(audioURL: URL) async throws -> [SpeakerSegment] {
        // Initialize if needed
        if !isInitialized {
            try await initialize()
        }

        guard let diarizer = diarizer else {
            throw DiarizationError.notInitialized
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw DiarizationError.audioFileNotFound(audioURL.path)
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            // Load and resample audio to 16kHz mono (required by FluidAudio)
            let converter = AudioConverter()
            let samples = try converter.resampleAudioFile(path: audioURL.path)

#if DEBUG
            print("SpeakerDiarizationService: [DEBUG] Processing audio with \(samples.count) samples (\(String(format: "%.1f", Float(samples.count) / 16000.0))s)")
#endif

            // Run diarization on audio samples
            let result = try await diarizer.process(audio: samples)

#if DEBUG
            print("SpeakerDiarizationService: [DEBUG] FluidAudio returned \(result.segments.count) raw segments")
            for (i, seg) in result.segments.enumerated() {
                let embeddingNorm = seg.embedding.isEmpty ? 0 : sqrt(seg.embedding.map { $0 * $0 }.reduce(0, +))
                print("  [DEBUG] Segment \(i): speaker=\(seg.speakerId), time=\(String(format: "%.1f", seg.startTimeSeconds))-\(String(format: "%.1f", seg.endTimeSeconds))s, quality=\(String(format: "%.2f", seg.qualityScore)), embedding_norm=\(String(format: "%.3f", embeddingNorm)), embedding_size=\(seg.embedding.count)")
            }
#endif

            // Build speaker ID mapping for cross-chunk consistency
            // Extract speaker data for mapping
            let speakerData = result.segments.map { (
                id: $0.speakerId.replacingOccurrences(of: "S", with: ""),
                embedding: $0.embedding
            )}
            let speakerIdMapping = buildSpeakerIdMapping(from: speakerData)

            // Convert FluidAudio results to our SpeakerSegment type
            // Apply speaker ID mapping for cross-chunk consistency
            let segments = result.segments.map { segment -> SpeakerSegment in
                // Convert FluidAudio's "S1", "S2" to numeric and apply mapping
                let rawId = segment.speakerId.replacingOccurrences(of: "S", with: "")
                let mappedId = speakerIdMapping[rawId] ?? rawId

                return SpeakerSegment(
                    speakerId: mappedId,
                    startTime: TimeInterval(segment.startTimeSeconds),
                    endTime: TimeInterval(segment.endTimeSeconds),
                    confidence: segment.qualityScore,
                    embedding: segment.embedding
                )
            }

#if DEBUG
            let uniqueSpeakers = Set(segments.map { $0.speakerId })
            print("SpeakerDiarizationService: [SUMMARY] Chunk has \(uniqueSpeakers.count) unique speakers (IDs: \(uniqueSpeakers.sorted().joined(separator: ", "))), \(segments.count) segments")
#endif

            return segments
        } catch let error as DiarizationError {
            self.error = error
            throw error
        } catch {
            let diarizationError = DiarizationError.diarizationFailed(error.localizedDescription)
            self.error = diarizationError
            throw diarizationError
        }
    }

    // MARK: - Merging with Transcription

    /// Merge diarization results with transcript segments
    /// This assigns specific speaker IDs to "Other" segments based on voice matching
    /// - Parameters:
    ///   - transcriptSegments: Segments from Whisper transcription
    ///   - speakerSegments: Segments from diarization
    /// - Returns: Transcript segments with speaker IDs assigned
    func mergeWithTranscript(
        transcriptSegments: [TranscriptSegment],
        speakerSegments: [SpeakerSegment]
    ) -> [TranscriptSegment] {
#if DEBUG
        print("SpeakerDiarizationService: [MERGE] Merging \(transcriptSegments.count) transcript segments with \(speakerSegments.count) diarization segments")
        print("  [MERGE] Transcript time range: \(String(format: "%.1f", transcriptSegments.first?.startTime ?? 0))-\(String(format: "%.1f", transcriptSegments.last?.endTime ?? 0))s")
        print("  [MERGE] Diarization time range: \(String(format: "%.1f", speakerSegments.first?.startTime ?? 0))-\(String(format: "%.1f", speakerSegments.last?.endTime ?? 0))s")
        for seg in speakerSegments {
            print("  [MERGE] Diarization segment: speaker=\(seg.speakerId), time=\(String(format: "%.1f", seg.startTime))-\(String(format: "%.1f", seg.endTime))s")
        }
#endif

        // Only process "Other" segments (system audio)
        // Clinician segments are already correctly attributed
        var matchCount = 0
        var noMatchCount = 0

        let result = transcriptSegments.map { segment in
            guard segment.speaker == .other else {
                return segment // Clinician segments unchanged
            }

            // Find the speaker segment that overlaps most with this transcript segment
            let bestMatch = findBestSpeakerMatch(
                transcriptStart: segment.startTime,
                transcriptEnd: segment.endTime,
                speakerSegments: speakerSegments
            )

            if let match = bestMatch {
                matchCount += 1
#if DEBUG
                print("  [MERGE] ✓ Transcript \(String(format: "%.1f", segment.startTime))-\(String(format: "%.1f", segment.endTime))s matched to speaker \(match.speakerId)")
#endif
                return TranscriptSegment(
                    id: segment.id,
                    speaker: segment.speaker,
                    text: segment.text,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    chunkIndex: segment.chunkIndex,
                    confidence: segment.confidence,
                    hasOverlap: segment.hasOverlap,
                    overlappingSegmentIds: segment.overlappingSegmentIds,
                    speakerId: match.speakerId,
                    speakerConfidence: match.confidence
                )
            }

            noMatchCount += 1
#if DEBUG
            print("  [MERGE] ✗ Transcript \(String(format: "%.1f", segment.startTime))-\(String(format: "%.1f", segment.endTime))s NO MATCH")
#endif
            return segment // No match found, return unchanged
        }

#if DEBUG
        print("SpeakerDiarizationService: [MERGE SUMMARY] \(matchCount) matched, \(noMatchCount) unmatched out of \(transcriptSegments.filter { $0.speaker == .other }.count) Other segments")
#endif

        return result
    }

    /// Find the speaker segment that best matches a transcript segment's time range
    private func findBestSpeakerMatch(
        transcriptStart: TimeInterval,
        transcriptEnd: TimeInterval,
        speakerSegments: [SpeakerSegment]
    ) -> SpeakerSegment? {
        var bestMatch: SpeakerSegment?
        var bestOverlap: TimeInterval = 0

        for speakerSeg in speakerSegments {
            // Calculate overlap
            let overlapStart = max(transcriptStart, speakerSeg.startTime)
            let overlapEnd = min(transcriptEnd, speakerSeg.endTime)
            let overlap = max(0, overlapEnd - overlapStart)

            if overlap > bestOverlap {
                bestOverlap = overlap
                bestMatch = speakerSeg
            }
        }

        // Only return match if there's meaningful overlap (at least 30% of transcript segment)
        // Lowered from 50% to improve matching coverage
        let transcriptDuration = transcriptEnd - transcriptStart
        if bestOverlap > transcriptDuration * 0.3 {
            return bestMatch
        }

#if DEBUG
        // Log when no match is found for debugging
        if bestOverlap > 0 {
            let overlapPercent = (bestOverlap / transcriptDuration) * 100
            print("SpeakerDiarizationService: No match for segment \(String(format: "%.1f", transcriptStart))-\(String(format: "%.1f", transcriptEnd))s, best overlap: \(String(format: "%.0f", overlapPercent))% (need 30%)")
        }
#endif

        return nil
    }

    // MARK: - Settings Check

    /// Check if enhanced diarization is enabled in settings
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.enhancedDiarizationEnabled)
    }

    // MARK: - Cross-Chunk Speaker Mapping

    /// Build a mapping from FluidAudio's chunk-local speaker IDs to consistent session-wide IDs
    /// On first chunk, stores reference embeddings. On subsequent chunks, maps based on embedding similarity.
    private func buildSpeakerIdMapping(from speakerData: [(id: String, embedding: [Float])]) -> [String: String] {
        // Collect unique speakers and their average embeddings from this chunk
        var chunkSpeakerEmbeddings: [String: [Float]] = [:]
        var chunkSpeakerCounts: [String: Int] = [:]

        for speaker in speakerData {
            let rawId = speaker.id
            guard !speaker.embedding.isEmpty else { continue }

            if chunkSpeakerEmbeddings[rawId] == nil {
                chunkSpeakerEmbeddings[rawId] = speaker.embedding
                chunkSpeakerCounts[rawId] = 1
            } else {
                // Average the embeddings for this speaker
                var existing = chunkSpeakerEmbeddings[rawId]!
                for i in 0..<min(existing.count, speaker.embedding.count) {
                    existing[i] += speaker.embedding[i]
                }
                chunkSpeakerEmbeddings[rawId] = existing
                chunkSpeakerCounts[rawId] = (chunkSpeakerCounts[rawId] ?? 0) + 1
            }
        }

        // Normalize averaged embeddings
        for (speakerId, count) in chunkSpeakerCounts {
            if var embedding = chunkSpeakerEmbeddings[speakerId], count > 1 {
                for i in 0..<embedding.count {
                    embedding[i] /= Float(count)
                }
                chunkSpeakerEmbeddings[speakerId] = embedding
            }
        }

        // First chunk: store as reference and use IDs as-is
        if referenceEmbeddings.isEmpty {
            referenceEmbeddings = chunkSpeakerEmbeddings
#if DEBUG
            print("SpeakerDiarizationService: [TRACKING] First chunk - stored \(referenceEmbeddings.count) reference embeddings (IDs: \(referenceEmbeddings.keys.sorted().joined(separator: ", ")))")
#endif
            // Return identity mapping
            return Dictionary(uniqueKeysWithValues: chunkSpeakerEmbeddings.keys.map { ($0, $0) })
        }

        // Subsequent chunks: find best mapping based on embedding distance
        var mapping: [String: String] = [:]
        var usedReferenceIds: Set<String> = []

        // Sort chunk speakers by total speech duration (process longer speakers first for better matching)
        let sortedChunkSpeakers = chunkSpeakerEmbeddings.keys.sorted { a, b in
            (chunkSpeakerCounts[a] ?? 0) > (chunkSpeakerCounts[b] ?? 0)
        }

        for chunkSpeakerId in sortedChunkSpeakers {
            guard let chunkEmbedding = chunkSpeakerEmbeddings[chunkSpeakerId] else { continue }

            var bestRefId: String?
            var bestDistance: Float = Float.infinity

            for (refId, refEmbedding) in referenceEmbeddings {
                guard !usedReferenceIds.contains(refId) else { continue }

                let distance = cosineDistance(chunkEmbedding, refEmbedding)
                if distance < bestDistance {
                    bestDistance = distance
                    bestRefId = refId
                }
            }

            if let refId = bestRefId {
                mapping[chunkSpeakerId] = refId
                usedReferenceIds.insert(refId)
#if DEBUG
                print("SpeakerDiarizationService: [TRACKING] Mapped chunk speaker \(chunkSpeakerId) → reference \(refId) (distance: \(String(format: "%.3f", bestDistance)))")
#endif
            } else {
                // No available reference speaker, keep original ID
                mapping[chunkSpeakerId] = chunkSpeakerId
#if DEBUG
                print("SpeakerDiarizationService: [TRACKING] No reference match for chunk speaker \(chunkSpeakerId), keeping original ID")
#endif
            }
        }

        return mapping
    }

    /// Compute cosine distance between two embeddings (0 = identical, 2 = opposite)
    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return Float.infinity }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return Float.infinity }

        let cosineSimilarity = dotProduct / denominator
        return 1.0 - cosineSimilarity  // Convert to distance
    }
}
