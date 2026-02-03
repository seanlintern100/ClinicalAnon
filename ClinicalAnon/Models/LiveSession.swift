//
//  LiveSession.swift
//  ClinicalAnon
//
//  Purpose: State container for a live recording session
//  Organization: 3 Big Things
//

import Foundation
import Combine

// MARK: - Session State

/// Represents the current state of a live recording session
enum SessionState: String, Codable, CaseIterable {
    case recording      // Audio capture active
    case paused         // Capture paused, can resume
    case complete       // Recording stopped, awaiting handoff
    case handedOff      // Transferred to Redact phase

    var displayName: String {
        switch self {
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .complete: return "Complete"
        case .handedOff: return "In Redact"
        }
    }

    var iconName: String {
        switch self {
        case .recording: return "record.circle"
        case .paused: return "pause.circle"
        case .complete: return "checkmark.circle"
        case .handedOff: return "arrow.right.circle"
        }
    }
}

// MARK: - Pause Gap

/// Represents a gap in recording due to pause
struct PauseGap: Codable, Hashable {
    let start: Date
    var end: Date?

    var duration: TimeInterval? {
        guard let end = end else { return nil }
        return end.timeIntervalSince(start)
    }
}

// MARK: - Live Session Data

/// Codable data container for LiveSession persistence
struct LiveSessionData: Codable {
    let id: UUID
    let createdAt: Date
    var state: SessionState
    var name: String
    var recordingDuration: TimeInterval
    var pausedAt: Date?
    var pauseGaps: [PauseGap]
    var transcriptSegments: [TranscriptSegment]
    var transcriptionGaps: [TranscriptionGap]
    var lastTranscriptUpdate: Date?
    var detectedEntities: [Entity]
    var audioChunkPaths: [AudioChunkReference]
    var assistantStateData: SessionAssistantStateData?  // AI assistant state (parking lot + feed)
    var chatMessages: [ChatMessage]?  // AI assistant chat history
    var hasMultipleParticipants: Bool?  // Speaker diarization toggle

    /// Initialize with explicit values (used for decoding)
    init(
        id: UUID,
        createdAt: Date,
        state: SessionState,
        name: String,
        recordingDuration: TimeInterval,
        pausedAt: Date?,
        pauseGaps: [PauseGap],
        transcriptSegments: [TranscriptSegment],
        transcriptionGaps: [TranscriptionGap],
        lastTranscriptUpdate: Date?,
        detectedEntities: [Entity],
        audioChunkPaths: [AudioChunkReference],
        assistantStateData: SessionAssistantStateData? = nil,
        chatMessages: [ChatMessage]? = nil,
        hasMultipleParticipants: Bool? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.state = state
        self.name = name
        self.recordingDuration = recordingDuration
        self.pausedAt = pausedAt
        self.pauseGaps = pauseGaps
        self.transcriptSegments = transcriptSegments
        self.transcriptionGaps = transcriptionGaps
        self.lastTranscriptUpdate = lastTranscriptUpdate
        self.detectedEntities = detectedEntities
        self.audioChunkPaths = audioChunkPaths
        self.assistantStateData = assistantStateData
        self.chatMessages = chatMessages
        self.hasMultipleParticipants = hasMultipleParticipants
    }

    /// Initialize from a LiveSession (must be called on MainActor)
    @MainActor
    init(from session: LiveSession, assistantState: SessionAssistantStateData? = nil) {
        self.id = session.id
        self.createdAt = session.createdAt
        self.state = session.state
        self.name = session.name
        self.recordingDuration = session.recordingDuration
        self.pausedAt = session.pausedAt
        self.pauseGaps = session.pauseGaps
        self.transcriptSegments = session.transcriptSegments
        self.transcriptionGaps = session.transcriptionGaps
        self.lastTranscriptUpdate = session.lastTranscriptUpdate
        self.detectedEntities = session.detectedEntities
        self.audioChunkPaths = session.audioChunkPaths
        self.assistantStateData = assistantState
        self.chatMessages = session.chatMessages
        self.hasMultipleParticipants = session.hasMultipleParticipants
    }
}

// MARK: - Live Session

/// Represents a single live recording session
@MainActor
class LiveSession: ObservableObject, Identifiable {

    // MARK: - Identity

    let id: UUID
    let createdAt: Date

    // MARK: - State

    @Published var state: SessionState
    @Published var name: String

    // MARK: - Timing

    @Published var recordingDuration: TimeInterval
    @Published var pausedAt: Date?
    @Published var pauseGaps: [PauseGap] = []

    // MARK: - Transcript

    @Published var transcriptSegments: [TranscriptSegment] = []
    @Published var transcriptionGaps: [TranscriptionGap] = []
    @Published var lastTranscriptUpdate: Date?

    // MARK: - Entities

    @Published var entityMapping: EntityMapping
    @Published var detectedEntities: [Entity] = []

    // MARK: - Audio References

    @Published var audioChunkPaths: [AudioChunkReference] = []

    // MARK: - Chat

    @Published var chatMessages: [ChatMessage] = []
    let conversationContext: ConversationContext

    // MARK: - Speaker Diarization

    /// When enabled, speaker diarization identifies multiple remote participants as "Other A", "Other B", etc.
    /// When disabled, all remote audio is labeled simply as "Other".
    @Published var hasMultipleParticipants: Bool = false

    // MARK: - Initialization

    init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        self.state = .recording
        self.name = ""
        self.recordingDuration = 0
        self.entityMapping = EntityMapping()
        self.conversationContext = ConversationContext()
    }

    /// Initialize from persisted data
    convenience init(from data: LiveSessionData) {
        self.init(id: data.id, createdAt: data.createdAt)
        self.state = data.state
        self.name = data.name
        self.recordingDuration = data.recordingDuration
        self.pausedAt = data.pausedAt
        self.pauseGaps = data.pauseGaps
        self.transcriptSegments = data.transcriptSegments
        self.transcriptionGaps = data.transcriptionGaps
        self.lastTranscriptUpdate = data.lastTranscriptUpdate
        self.detectedEntities = data.detectedEntities
        self.audioChunkPaths = data.audioChunkPaths
        self.chatMessages = data.chatMessages ?? []
        self.hasMultipleParticipants = data.hasMultipleParticipants ?? false
    }

    // MARK: - Data Export

    /// Export session data for persistence
    var sessionData: LiveSessionData {
        LiveSessionData(from: self)
    }

    // MARK: - Computed Properties

    /// Display name, using timestamp if no custom name set
    var displayName: String {
        name.isEmpty ? formattedTimestamp : name
    }

    /// Formatted creation timestamp
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "Session – \(formatter.string(from: createdAt))"
    }

    /// Formatted duration string (e.g., "12:34")
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Full raw transcript (unredacted) for handoff
    var rawTranscript: String {
        transcriptSegments
            .sorted { $0.startTime < $1.startTime }
            .map { "[\($0.speaker.label)] \($0.text)" }
            .joined(separator: "\n\n")
    }

    /// Redacted transcript for AI context
    var redactedTranscript: String {
        var result = rawTranscript
        // Apply entity replacements sorted by position (descending) to avoid index shifts
        let sortedEntities = detectedEntities.sorted { entity1, entity2 in
            let pos1 = entity1.positions.first?.first ?? 0
            let pos2 = entity2.positions.first?.first ?? 0
            return pos1 > pos2
        }
        for entity in sortedEntities {
            result = result.replacingOccurrences(
                of: entity.originalText,
                with: entity.replacementCode,
                options: .caseInsensitive
            )
        }
        return result
    }

    /// Total pause duration
    var totalPauseDuration: TimeInterval {
        pauseGaps.compactMap { $0.duration }.reduce(0, +)
    }

    /// Number of completed audio chunks
    var completedChunkCount: Int {
        Set(audioChunkPaths.filter { $0.isProcessed }.map { $0.chunkIndex }).count
    }

    /// Number of transcript segments
    var segmentCount: Int {
        transcriptSegments.count
    }

    /// Whether the session can be edited (not handed off)
    var isEditable: Bool {
        state != .handedOff
    }

    /// Whether recording can be resumed
    var canResume: Bool {
        state == .paused
    }

    /// Whether the session can be handed off to Redact phase
    var canHandoff: Bool {
        state == .complete && !transcriptSegments.isEmpty
    }
}

// MARK: - Hashable & Equatable

extension LiveSession: Hashable {
    nonisolated static func == (lhs: LiveSession, rhs: LiveSession) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension LiveSession {
    /// Sample session for previews
    @MainActor
    static var sample: LiveSession {
        let session = LiveSession()
        session.name = "Morning Consultation"
        session.recordingDuration = 754  // 12:34
        session.state = .recording
        session.transcriptSegments = TranscriptSegment.samples
        return session
    }

    /// Completed session for previews
    @MainActor
    static var completed: LiveSession {
        let session = LiveSession()
        session.name = "Patient Follow-up"
        session.recordingDuration = 1847  // 30:47
        session.state = .complete
        session.transcriptSegments = TranscriptSegment.samples
        return session
    }

    /// Paused session for previews
    @MainActor
    static var paused: LiveSession {
        let session = LiveSession()
        session.name = "Intake Assessment"
        session.recordingDuration = 423
        session.state = .paused
        session.pausedAt = Date()
        return session
    }

    /// Sample sessions list
    @MainActor
    static var samples: [LiveSession] {
        [.sample, .completed, .paused]
    }
}
#endif
