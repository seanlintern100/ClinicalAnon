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

    // MARK: - Cross-Chunk Speaker Tracking (DISABLED)
    // Note: Cross-chunk tracking was causing speaker merging issues.
    // Each chunk now has independent speaker IDs (1, 2) that may not match across chunks.

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
        isInitialized = false
    }

    /// Reset speaker tracking for a new session
    /// Note: Cross-chunk tracking is currently disabled, so this is a no-op
    func resetSpeakerTracking() {
#if DEBUG
        print("SpeakerDiarizationService: New session started (cross-chunk tracking disabled)")
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

            // Convert FluidAudio results to our SpeakerSegment type
            // Use FluidAudio's native speaker IDs directly (e.g., "S1", "S2")
            // Note: Cross-chunk SpeakerManager tracking disabled - it was causing issues
            // by merging distinct speakers when first chunk had problematic embeddings
            let segments = result.segments.map { segment -> SpeakerSegment in
                // Convert FluidAudio's "S1", "S2" to numeric "1", "2" for consistency
                let speakerId = segment.speakerId.replacingOccurrences(of: "S", with: "")

                return SpeakerSegment(
                    speakerId: speakerId,
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
}
