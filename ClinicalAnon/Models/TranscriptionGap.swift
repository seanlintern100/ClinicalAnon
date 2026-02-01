//
//  TranscriptionGap.swift
//  ClinicalAnon
//
//  Purpose: Represents a gap in the transcript (pause or transcription failure)
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Gap Reason

/// Reason for a gap in the transcript
enum GapReason: String, Codable, CaseIterable {
    case paused = "Paused"
    case transcriptionFailed = "Transcription failed"
    case audioCorrupted = "Audio corrupted"
    case noSpeech = "No speech detected"

    /// User-friendly description
    var description: String {
        switch self {
        case .paused:
            return "Recording was paused"
        case .transcriptionFailed:
            return "Transcription could not process this audio"
        case .audioCorrupted:
            return "Audio file was corrupted or unreadable"
        case .noSpeech:
            return "No speech was detected in this audio"
        }
    }

    /// Icon name for SF Symbols
    var iconName: String {
        switch self {
        case .paused: return "pause.circle"
        case .transcriptionFailed: return "exclamationmark.triangle"
        case .audioCorrupted: return "waveform.slash"
        case .noSpeech: return "speaker.slash"
        }
    }

    /// Whether this type of gap might be recoverable
    var isPotentiallyRecoverable: Bool {
        switch self {
        case .paused, .noSpeech:
            return false
        case .transcriptionFailed, .audioCorrupted:
            return true
        }
    }
}

// MARK: - Transcription Gap

/// Represents a gap in the transcript due to pause or failure
struct TranscriptionGap: Identifiable, Codable, Hashable {

    // MARK: - Properties

    /// Unique identifier
    let id: UUID

    /// Reason for the gap
    let reason: GapReason

    /// Start time in seconds from session start
    let startTime: TimeInterval

    /// End time in seconds from session start
    var endTime: TimeInterval

    /// Which audio chunk failed (nil for pauses)
    let chunkIndex: Int?

    /// Whether user can retry transcription with a larger model
    let canRetry: Bool

    /// Error message if transcription failed
    let errorMessage: String?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        reason: GapReason,
        startTime: TimeInterval,
        endTime: TimeInterval,
        chunkIndex: Int? = nil,
        canRetry: Bool = false,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.reason = reason
        self.startTime = startTime
        self.endTime = endTime
        self.chunkIndex = chunkIndex
        self.canRetry = canRetry
        self.errorMessage = errorMessage
    }

    // MARK: - Computed Properties

    /// Duration of this gap in seconds
    var duration: TimeInterval {
        endTime - startTime
    }

    /// Display text for showing in transcript (e.g., "[Gap: 12:34 – 15:00 – Paused]")
    var displayText: String {
        let startFormatted = formatTime(startTime)
        let endFormatted = formatTime(endTime)
        return "[Gap: \(startFormatted) – \(endFormatted) – \(reason.rawValue)]"
    }

    /// Short display for compact views
    var shortDisplay: String {
        "[\(reason.rawValue): \(formattedDuration)]"
    }

    /// Formatted duration
    var formattedDuration: String {
        formatTime(duration)
    }

    /// Whether this gap was from a pause
    var isPause: Bool {
        reason == .paused
    }

    /// Whether this gap represents a failure that might be fixable
    var isRecoverable: Bool {
        canRetry && reason.isPotentiallyRecoverable
    }

    // MARK: - Private Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Factory Methods

extension TranscriptionGap {
    /// Create a pause gap
    static func pause(at time: TimeInterval) -> TranscriptionGap {
        TranscriptionGap(
            reason: .paused,
            startTime: time,
            endTime: time,
            canRetry: false
        )
    }

    /// Create a transcription failure gap
    static func transcriptionFailed(
        chunkIndex: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        error: String? = nil
    ) -> TranscriptionGap {
        TranscriptionGap(
            reason: .transcriptionFailed,
            startTime: startTime,
            endTime: endTime,
            chunkIndex: chunkIndex,
            canRetry: true,
            errorMessage: error
        )
    }

    /// Create an audio corrupted gap
    static func audioCorrupted(
        chunkIndex: Int,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> TranscriptionGap {
        TranscriptionGap(
            reason: .audioCorrupted,
            startTime: startTime,
            endTime: endTime,
            chunkIndex: chunkIndex,
            canRetry: false
        )
    }

    /// Create a no speech gap
    static func noSpeech(
        chunkIndex: Int,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> TranscriptionGap {
        TranscriptionGap(
            reason: .noSpeech,
            startTime: startTime,
            endTime: endTime,
            chunkIndex: chunkIndex,
            canRetry: false
        )
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension TranscriptionGap {
    /// Sample pause gap for previews
    static var samplePause: TranscriptionGap {
        TranscriptionGap(
            reason: .paused,
            startTime: 300,
            endTime: 360,
            canRetry: false
        )
    }

    /// Sample failure gap for previews
    static var sampleFailure: TranscriptionGap {
        TranscriptionGap(
            reason: .transcriptionFailed,
            startTime: 180,
            endTime: 360,
            chunkIndex: 1,
            canRetry: true,
            errorMessage: "Model failed to process audio segment"
        )
    }

    /// Sample gaps list
    static var samples: [TranscriptionGap] {
        [
            TranscriptionGap(
                reason: .paused,
                startTime: 300,
                endTime: 360,
                canRetry: false
            ),
            TranscriptionGap(
                reason: .transcriptionFailed,
                startTime: 540,
                endTime: 720,
                chunkIndex: 3,
                canRetry: true,
                errorMessage: "Model timeout"
            ),
            TranscriptionGap(
                reason: .noSpeech,
                startTime: 900,
                endTime: 930,
                chunkIndex: 5,
                canRetry: false
            )
        ]
    }
}
#endif
