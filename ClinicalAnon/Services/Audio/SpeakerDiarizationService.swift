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
    case sessionNotActive

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
        case .sessionNotActive:
            return "No active diarization session. Call startSession() first."
        }
    }
}

// MARK: - Speaker Segment

/// Represents a segment of audio attributed to a specific speaker
struct SpeakerSegment {
    /// Speaker identifier (e.g., "SPEAKER_00", "SPEAKER_01")
    let speakerId: String

    /// Start time in seconds
    let startTime: TimeInterval

    /// End time in seconds
    let endTime: TimeInterval

    /// Confidence of speaker identification (0-1)
    let confidence: Float

    /// Duration of this segment
    var duration: TimeInterval {
        endTime - startTime
    }
}

// MARK: - Speaker Diarization Service

/// Service for identifying and separating multiple speakers in audio
/// Uses FluidAudio's DiarizerManager for on-device diarization with cross-chunk speaker tracking
@MainActor
class SpeakerDiarizationService: ObservableObject {

    // MARK: - Singleton

    static let shared = SpeakerDiarizationService()

    // MARK: - Published State

    @Published private(set) var isInitialized: Bool = false
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var sessionActive: Bool = false
    @Published private(set) var error: DiarizationError?

    // MARK: - FluidAudio Diarizer (Streaming with cross-chunk tracking)

    private var diarizer: DiarizerManager?
    private var models: DiarizerModels?

    /// Cumulative time offset for cross-chunk timestamp tracking
    private var cumulativeTimeOffset: TimeInterval = 0

    // MARK: - Initialization

    private init() {}

    /// Load diarization models (call once during app startup)
    func loadModels() async throws {
        guard !isInitialized else { return }

        do {
            print("SpeakerDiarizationService: Loading FluidAudio models...")
            models = try await DiarizerModels.download()
            isInitialized = true
            print("SpeakerDiarizationService: Models loaded successfully")
        } catch {
            self.error = .modelLoadFailed(error.localizedDescription)
            throw DiarizationError.modelLoadFailed(error.localizedDescription)
        }
    }

    // MARK: - Session Lifecycle

    /// Start a new diarization session (call when recording starts)
    /// This creates a new DiarizerManager that will track speakers across chunks
    func startSession() async throws {
        // Load models if not already initialized
        if !isInitialized {
            try await loadModels()
        }

        guard let models = self.models else {
            throw DiarizationError.notInitialized
        }

        // Create fresh diarizer for this session with speaker tracking
        let config = DiarizerConfig(
            clusteringThreshold: 0.7,     // Optimal for speaker grouping
            minSpeechDuration: 1.0,       // Minimum 1 second speech
            minEmbeddingUpdateDuration: 2.0,
            minSilenceGap: 0.5,
            numClusters: -1,              // Auto-detect speaker count
            minActiveFramesCount: 10.0,
            debugMode: false
        )

        diarizer = DiarizerManager(config: config)
        diarizer?.initialize(models: models)

        cumulativeTimeOffset = 0
        sessionActive = true

        print("SpeakerDiarizationService: Session started - cross-chunk speaker tracking enabled")
    }

    /// End the diarization session (call when recording stops)
    func endSession() {
        diarizer?.cleanup()
        diarizer = nil
        sessionActive = false
        cumulativeTimeOffset = 0
        print("SpeakerDiarizationService: Session ended - speaker state cleared")
    }

    // MARK: - Diarization

    /// Process audio samples for the current session
    /// Speaker IDs are maintained across calls within the same session
    /// - Parameters:
    ///   - samples: Audio samples (16kHz mono)
    ///   - chunkDuration: Duration of this chunk in seconds (for time offset tracking)
    /// - Returns: Array of speaker segments with timing and speaker IDs
    func processSamples(_ samples: [Float], chunkDuration: TimeInterval) async throws -> [SpeakerSegment] {
        guard sessionActive, let diarizer = diarizer else {
            throw DiarizationError.sessionNotActive
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            // Process samples with time offset for session-level timestamps
            let result = try diarizer.performCompleteDiarization(
                samples,
                sampleRate: 16000,
                atTime: cumulativeTimeOffset
            )

            // Update cumulative time offset for next chunk
            cumulativeTimeOffset += chunkDuration

            // Convert FluidAudio results to our SpeakerSegment type
            let segments = result.segments.map { segment in
                SpeakerSegment(
                    speakerId: segment.speakerId,
                    startTime: TimeInterval(segment.startTimeSeconds),
                    endTime: TimeInterval(segment.endTimeSeconds),
                    confidence: segment.qualityScore
                )
            }

#if DEBUG
            let uniqueSpeakers = Set(segments.map { $0.speakerId })
            print("SpeakerDiarizationService: Found \(uniqueSpeakers.count) speakers, \(segments.count) segments (time offset: \(String(format: "%.1f", cumulativeTimeOffset))s)")
#endif

            return segments
        } catch let error as DiarizerError {
            self.error = .diarizationFailed(error.localizedDescription)
            throw DiarizationError.diarizationFailed(error.localizedDescription)
        } catch {
            let diarizationError = DiarizationError.diarizationFailed(error.localizedDescription)
            self.error = diarizationError
            throw diarizationError
        }
    }

    /// Legacy method: Diarize from file URL (for backwards compatibility)
    /// Note: This creates a one-off diarization without session tracking
    func diarize(audioURL: URL) async throws -> [SpeakerSegment] {
        // If session is active, use session-aware processing
        if sessionActive {
            let converter = AudioConverter()
            let samples = try converter.resampleAudioFile(path: audioURL.path)
            let duration = TimeInterval(samples.count) / 16000.0
            return try await processSamples(samples, chunkDuration: duration)
        }

        // Fallback: one-off diarization without session tracking
        // Load models if not already initialized
        if !isInitialized {
            try await loadModels()
        }

        guard let models = self.models else {
            throw DiarizationError.notInitialized
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw DiarizationError.audioFileNotFound(audioURL.path)
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            // Create temporary diarizer for one-off processing
            let config = DiarizerConfig()
            let tempDiarizer = DiarizerManager(config: config)
            tempDiarizer.initialize(models: models)

            let converter = AudioConverter()
            let samples = try converter.resampleAudioFile(path: audioURL.path)

            let result = try tempDiarizer.performCompleteDiarization(samples, sampleRate: 16000)

            tempDiarizer.cleanup()

            let segments = result.segments.map { segment in
                SpeakerSegment(
                    speakerId: segment.speakerId,
                    startTime: TimeInterval(segment.startTimeSeconds),
                    endTime: TimeInterval(segment.endTimeSeconds),
                    confidence: segment.qualityScore
                )
            }

#if DEBUG
            let uniqueSpeakers = Set(segments.map { $0.speakerId })
            print("SpeakerDiarizationService: Found \(uniqueSpeakers.count) speakers, \(segments.count) segments (one-off)")
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
        // Only process "Other" segments (system audio)
        // Clinician segments are already correctly attributed
        return transcriptSegments.map { segment in
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

            return segment // No match found, return unchanged
        }
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

        // Only return match if there's meaningful overlap (at least 50% of transcript segment)
        let transcriptDuration = transcriptEnd - transcriptStart
        if bestOverlap > transcriptDuration * 0.5 {
            return bestMatch
        }

        return nil
    }

    // MARK: - Settings Check

    /// Check if enhanced diarization is enabled in settings
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.enhancedDiarizationEnabled)
    }
}
