//
//  SpeakerDiarizationService.swift
//  ClinicalAnon
//
//  Purpose: Speaker diarization using FluidAudio for identifying multiple remote speakers
//  Organization: 3 Big Things
//

import Foundation
import AVFoundation
import FluidAudio

// MARK: - Diarization Error

enum DiarizationError: Error, LocalizedError {
    case notInitialized
    case modelLoadFailed(String)
    case diarizationFailed(String)
    case audioFileNotFound(String)
    case audioLoadFailed(String)

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
        case .audioLoadFailed(let reason):
            return "Failed to load audio: \(reason)"
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
/// Uses FluidAudio's OfflineDiarizerManager (pyannote-based) for on-device diarization
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

    // MARK: - Initialization

    private init() {}

    /// Initialize the diarization model
    /// Call this before first use (can be called during app startup or lazily)
    func initialize() async throws {
        guard !isInitialized else { return }

        do {
            let config = OfflineDiarizerConfig()
            diarizer = OfflineDiarizerManager(config: config)
            try await diarizer?.prepareModels()
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

    // MARK: - Diarization

    /// Diarize audio to identify distinct speakers
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
            // Load audio samples from file
            let samples = try await loadAudioSamples(from: audioURL)

            // Run diarization
            let result = try await diarizer.process(audio: samples)

            // Convert FluidAudio results to our SpeakerSegment type
            let segments = result.map { segment in
                SpeakerSegment(
                    speakerId: segment.speaker,
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end),
                    confidence: segment.confidence ?? 1.0
                )
            }

#if DEBUG
            let uniqueSpeakers = Set(segments.map { $0.speakerId })
            print("SpeakerDiarizationService: Found \(uniqueSpeakers.count) speakers, \(segments.count) segments")
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

    // MARK: - Audio Loading

    /// Load audio samples from a file URL
    private func loadAudioSamples(from url: URL) async throws -> [Float] {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw DiarizationError.audioLoadFailed(error.localizedDescription)
        }

        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw DiarizationError.audioLoadFailed("Failed to create audio buffer")
        }

        do {
            try audioFile.read(into: buffer)
        } catch {
            throw DiarizationError.audioLoadFailed(error.localizedDescription)
        }

        guard let channelData = buffer.floatChannelData else {
            throw DiarizationError.audioLoadFailed("No channel data in buffer")
        }

        // Convert to mono if stereo
        let channelCount = Int(format.channelCount)
        var samples = [Float](repeating: 0, count: Int(buffer.frameLength))

        if channelCount == 1 {
            // Mono - just copy
            for i in 0..<Int(buffer.frameLength) {
                samples[i] = channelData[0][i]
            }
        } else {
            // Stereo - mix to mono
            for i in 0..<Int(buffer.frameLength) {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                samples[i] = sum / Float(channelCount)
            }
        }

        return samples
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
