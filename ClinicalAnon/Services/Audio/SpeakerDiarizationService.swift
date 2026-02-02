//
//  SpeakerDiarizationService.swift
//  ClinicalAnon
//
//  Purpose: Speaker diarization for identifying multiple remote speakers
//  Organization: 3 Big Things
//
//  NOTE: Full implementation requires Argmax Pro SDK license for SpeakerKit.
//  See: https://www.argmaxinc.com/blog/speakerkit
//
//  This is a placeholder that provides the interface. When SpeakerKit license
//  is obtained, uncomment the import and implement the diarize() method.
//

import Foundation
// import SpeakerKit  // Requires Argmax Pro SDK license

// MARK: - Diarization Error

enum DiarizationError: Error, LocalizedError {
    case notInitialized
    case notAvailable
    case modelLoadFailed(String)
    case diarizationFailed(String)
    case audioFileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Speaker diarization service is not initialized."
        case .notAvailable:
            return "Speaker diarization requires Argmax Pro SDK license. See Settings for details."
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
///
/// NOTE: Full implementation requires Argmax Pro SDK license for SpeakerKit.
/// Currently this is a placeholder that returns the setting check but doesn't
/// actually perform diarization. The infrastructure (settings, UI, data model)
/// is in place for when the license is obtained.
@MainActor
class SpeakerDiarizationService: ObservableObject {

    // MARK: - Singleton

    static let shared = SpeakerDiarizationService()

    // MARK: - Published State

    @Published private(set) var isInitialized: Bool = false
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var error: DiarizationError?

    // MARK: - Initialization

    private init() {
        // SpeakerKit requires Argmax Pro SDK license
        // When license is obtained, initialize here
        isAvailable = false
    }

    /// Initialize the diarization model
    /// Currently a no-op until SpeakerKit license is obtained
    func initialize() async throws {
        // TODO: When SpeakerKit license is obtained:
        // speakerKit = try await SpeakerKit()
        // isInitialized = true
        // isAvailable = true

        throw DiarizationError.notAvailable
    }

    /// Unload the model to free memory
    func unload() {
        isInitialized = false
    }

    // MARK: - Diarization

    /// Diarize audio to identify distinct speakers
    /// - Parameter audioURL: URL to the audio file
    /// - Returns: Array of speaker segments with timing and speaker IDs
    func diarize(audioURL: URL) async throws -> [SpeakerSegment] {
        guard isAvailable else {
            throw DiarizationError.notAvailable
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw DiarizationError.audioFileNotFound(audioURL.path)
        }

        isProcessing = true
        defer { isProcessing = false }

        // TODO: When SpeakerKit license is obtained:
        // let result = try await speakerKit.diarize(audioURL)
        // return result.segments.map { ... }

        throw DiarizationError.notAvailable
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
    /// Note: Even if enabled, feature requires Argmax Pro SDK license
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.enhancedDiarizationEnabled)
    }

    /// Check if the feature is available (licensed)
    static var isFeatureAvailable: Bool {
        return SpeakerDiarizationService.shared.isAvailable
    }
}
