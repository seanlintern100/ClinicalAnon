//
//  SpeakerDiarizationService.swift
//  ClinicalAnon
//
//  Purpose: Speaker diarization using SpeakerKit for identifying multiple remote speakers
//  Organization: 3 Big Things
//

import Foundation
import SpeakerKit

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
/// Uses SpeakerKit (from Argmax, same team as WhisperKit) for on-device diarization
@MainActor
class SpeakerDiarizationService: ObservableObject {

    // MARK: - Singleton

    static let shared = SpeakerDiarizationService()

    // MARK: - Published State

    @Published private(set) var isInitialized: Bool = false
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var error: DiarizationError?

    // MARK: - SpeakerKit Instance

    private var speakerKit: SpeakerKit?

    // MARK: - Initialization

    private init() {}

    /// Initialize the diarization model
    /// Call this before first use (can be called during app startup or lazily)
    func initialize() async throws {
        guard !isInitialized else { return }

        do {
            speakerKit = try await SpeakerKit()
            isInitialized = true
#if DEBUG
            print("SpeakerDiarizationService: SpeakerKit initialized successfully")
#endif
        } catch {
            self.error = .modelLoadFailed(error.localizedDescription)
            throw DiarizationError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Unload the model to free memory
    func unload() {
        speakerKit = nil
        isInitialized = false
    }

    // MARK: - Diarization

    /// Diarize audio to identify distinct speakers
    /// - Parameter audioURL: URL to the audio file
    /// - Returns: Array of speaker segments with timing and speaker IDs
    func diarize(audioURL: URL) async throws -> [SpeakerSegment] {
        guard let kit = speakerKit else {
            // Try to initialize if not already
            if !isInitialized {
                try await initialize()
            }
            guard let kit = speakerKit else {
                throw DiarizationError.notInitialized
            }
            return try await performDiarization(kit: kit, audioURL: audioURL)
        }

        return try await performDiarization(kit: kit, audioURL: audioURL)
    }

    private func performDiarization(kit: SpeakerKit, audioURL: URL) async throws -> [SpeakerSegment] {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw DiarizationError.audioFileNotFound(audioURL.path)
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let result = try await kit.diarize(audioURL)

            // Convert SpeakerKit results to our SpeakerSegment type
            let segments = result.segments.map { segment in
                SpeakerSegment(
                    speakerId: segment.speaker,
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end),
                    confidence: segment.confidence
                )
            }

#if DEBUG
            let uniqueSpeakers = Set(segments.map { $0.speakerId })
            print("SpeakerDiarizationService: Found \(uniqueSpeakers.count) speakers, \(segments.count) segments")
#endif

            return segments
        } catch {
            self.error = .diarizationFailed(error.localizedDescription)
            throw DiarizationError.diarizationFailed(error.localizedDescription)
        }
    }

    // MARK: - Merging with Transcription

    /// Merge diarization results with transcript segments
    /// This assigns specific speaker IDs to "Other" segments based on voice matching
    /// - Parameters:
    ///   - transcriptSegments: Segments from Whisper transcription
    ///   - speakerSegments: Segments from SpeakerKit diarization
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
