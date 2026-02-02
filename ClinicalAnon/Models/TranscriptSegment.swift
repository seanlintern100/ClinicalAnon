//
//  TranscriptSegment.swift
//  ClinicalAnon
//
//  Purpose: Represents a segment of transcribed speech with timing and speaker info
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Speaker

/// Represents the source of audio for a transcript segment
enum Speaker: String, Codable, CaseIterable {
    case clinician = "Clinician"
    case other = "Other"

    /// Display label for UI
    var label: String { rawValue }

    /// Short label for compact display
    var shortLabel: String {
        switch self {
        case .clinician: return "C"
        case .other: return "O"
        }
    }

    /// Icon name for SF Symbols
    var iconName: String {
        switch self {
        case .clinician: return "person.fill"
        case .other: return "person.2.fill"
        }
    }

    /// Color name for distinguishing speakers
    var colorName: String {
        switch self {
        case .clinician: return "blue"
        case .other: return "green"
        }
    }
}

// MARK: - Transcript Segment

/// A segment of transcribed speech with timing and speaker information
struct TranscriptSegment: Identifiable, Codable, Hashable {

    // MARK: - Properties

    /// Unique identifier
    let id: UUID

    /// Who spoke this segment
    let speaker: Speaker

    /// The transcribed text
    let text: String

    /// Start time in seconds from session start
    let startTime: TimeInterval

    /// End time in seconds from session start
    let endTime: TimeInterval

    /// Which audio chunk this segment came from
    let chunkIndex: Int

    /// Whisper confidence score (0-1), if available
    let confidence: Double?

    /// Whether this segment overlaps with speech from another speaker
    var hasOverlap: Bool

    /// IDs of segments that overlap with this one
    var overlappingSegmentIds: [UUID]

    /// Voice-based speaker ID from diarization (e.g., "SPEAKER_00", "SPEAKER_01")
    /// Only populated when enhanced speaker identification is enabled
    var speakerId: String?

    /// Confidence of speaker identification (0-1)
    var speakerConfidence: Float?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        speaker: Speaker,
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        chunkIndex: Int,
        confidence: Double? = nil,
        hasOverlap: Bool = false,
        overlappingSegmentIds: [UUID] = [],
        speakerId: String? = nil,
        speakerConfidence: Float? = nil
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.chunkIndex = chunkIndex
        self.confidence = confidence
        self.hasOverlap = hasOverlap
        self.speakerId = speakerId
        self.speakerConfidence = speakerConfidence
        self.overlappingSegmentIds = overlappingSegmentIds
    }

    // MARK: - Computed Properties

    /// Duration of this segment in seconds
    var duration: TimeInterval {
        endTime - startTime
    }

    /// Formatted start time for display (e.g., "12:34")
    var formattedStartTime: String {
        formatTime(startTime)
    }

    /// Formatted end time for display
    var formattedEndTime: String {
        formatTime(endTime)
    }

    /// Formatted duration for display
    var formattedDuration: String {
        formatTime(duration)
    }

    /// Whether this segment has low confidence (below 0.7)
    var isLowConfidence: Bool {
        guard let conf = confidence else { return false }
        return conf < 0.7
    }

    /// Whether this segment may have transcription issues (overlap or low confidence)
    var mayHaveIssues: Bool {
        hasOverlap || isLowConfidence
    }

    /// Word count for this segment
    var wordCount: Int {
        text.split(separator: " ").count
    }

    // MARK: - Private Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension TranscriptSegment {
    /// Sample segment for previews
    static var sample: TranscriptSegment {
        TranscriptSegment(
            speaker: .clinician,
            text: "Good morning, how are you feeling today?",
            startTime: 0,
            endTime: 3.5,
            chunkIndex: 0,
            confidence: 0.95
        )
    }

    /// Sample segments for list previews
    static var samples: [TranscriptSegment] {
        [
            TranscriptSegment(
                speaker: .clinician,
                text: "Good morning, how are you feeling today?",
                startTime: 0,
                endTime: 3.5,
                chunkIndex: 0,
                confidence: 0.95
            ),
            TranscriptSegment(
                speaker: .other,
                text: "I've been having some trouble sleeping lately. The pain keeps me awake most nights.",
                startTime: 4.0,
                endTime: 9.2,
                chunkIndex: 0,
                confidence: 0.92
            ),
            TranscriptSegment(
                speaker: .clinician,
                text: "I see. Can you tell me more about the pain? Where exactly is it located?",
                startTime: 10.0,
                endTime: 14.5,
                chunkIndex: 0,
                confidence: 0.98
            ),
            TranscriptSegment(
                speaker: .other,
                text: "It's mostly in my lower back, but sometimes it radiates down my left leg.",
                startTime: 15.0,
                endTime: 20.3,
                chunkIndex: 0,
                confidence: 0.89
            ),
            TranscriptSegment(
                speaker: .clinician,
                text: "And how would you rate the pain on a scale of 1 to 10?",
                startTime: 21.0,
                endTime: 24.5,
                chunkIndex: 0,
                confidence: 0.96
            )
        ]
    }

    /// Low confidence segment for testing
    static var lowConfidence: TranscriptSegment {
        TranscriptSegment(
            speaker: .other,
            text: "[inaudible] something about the medication [unclear]",
            startTime: 180.0,
            endTime: 185.0,
            chunkIndex: 1,
            confidence: 0.45
        )
    }
}
#endif
