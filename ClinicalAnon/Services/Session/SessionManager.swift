//
//  SessionManager.swift
//  ClinicalAnon
//
//  Purpose: Central coordinator for all live recording sessions
//  Organization: 3 Big Things
//

import Foundation
import Combine

// MARK: - Session Manager

/// Manages all live recording sessions
@MainActor
class SessionManager: ObservableObject {

    // MARK: - Singleton

    static let shared = SessionManager()

    // MARK: - Published State

    @Published private(set) var sessions: [LiveSession] = []
    @Published private(set) var activeSession: LiveSession?
    @Published private(set) var isRestoring: Bool = false
    @Published private(set) var isSessionModeActive: Bool = false

    // MARK: - Services

    private let audioCaptureService = AudioCaptureService()
    private let transcriptionService = TranscriptionService.shared
    private let storageService = SessionStorageService.shared

    // MARK: - Session Assistant

    private(set) lazy var assistantService: SessionAssistantService = {
        let bedrockService = BedrockService()
        let preferencesManager = ClinicianPreferencesManager()
        return SessionAssistantService(bedrockService: bedrockService, preferencesManager: preferencesManager)
    }()

    // MARK: - Duration Timer

    private var durationTimer: Timer?
    private var sessionStartDate: Date?

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        setupNotificationObservers()
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // Listen for transcription results
        NotificationCenter.default.publisher(for: .transcriptionComplete)
            .sink { [weak self] notification in
                guard let result = notification.object as? TranscriptionResult else { return }
                Task { @MainActor in
                    self?.handleTranscriptionResult(result)
                }
            }
            .store(in: &cancellables)

        // Listen for transcription failures
        NotificationCenter.default.publisher(for: .transcriptionFailed)
            .sink { [weak self] notification in
                guard let failure = notification.object as? TranscriptionFailure else { return }
                Task { @MainActor in
                    self?.handleTranscriptionFailure(failure)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Session Mode

    /// Enter session mode (show session UI)
    func enterSessionMode() {
        isSessionModeActive = true
    }

    /// Exit session mode (return to normal workflow)
    func exitSessionMode() {
        isSessionModeActive = false
    }

    // MARK: - Session Lifecycle

    /// Start a new recording session
    func startSession() async throws -> LiveSession {
        // Don't wait for transcription model here - it will load when needed
        // This allows session to start immediately
        // Model loading happens in background when first audio chunk is ready

        // Reset assistant for new session
        assistantService.reset()

        let session = LiveSession()
        sessions.insert(session, at: 0)  // Add to beginning (most recent)
        activeSession = session

        // Create session directory
        try storageService.createSessionDirectory(for: session)

        // Start audio capture
        try await audioCaptureService.startCapture(for: session)

        // Start duration timer
        startDurationTimer(for: session)

        // Auto-save session
        try await storageService.saveSession(session)

        return session
    }

    // MARK: - Duration Timer

    private func startDurationTimer(for session: LiveSession) {
        // Only set start date on initial start, not on resume
        if sessionStartDate == nil {
            sessionStartDate = Date()
            print("SessionManager: Started duration timer with start date \(sessionStartDate!)")
        }
        durationTimer?.invalidate()

        // Create timer and explicitly add to main RunLoop
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard session.state == .recording else {
                    print("SessionManager: Timer tick but session not recording (state: \(session.state))")
                    return
                }
                if let startDate = self.sessionStartDate {
                    // Calculate total pause time
                    let totalPauseTime = session.pauseGaps.reduce(0.0) { total, gap in
                        if let end = gap.end {
                            return total + end.timeIntervalSince(gap.start)
                        }
                        return total
                    }
                    let newDuration = Date().timeIntervalSince(startDate) - totalPauseTime
                    session.recordingDuration = newDuration
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        durationTimer = timer
        print("SessionManager: Timer added to main RunLoop")
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func resetDurationTimer() {
        stopDurationTimer()
        sessionStartDate = nil
    }

    /// Pause the active session
    func pauseSession(_ session: LiveSession) {
        guard session.state == .recording else { return }

        stopDurationTimer()

        session.state = .paused
        session.pausedAt = Date()

        // Record pause gap start
        session.pauseGaps.append(PauseGap(start: Date(), end: nil))

        audioCaptureService.pauseCapture()

        // Create pause gap in transcript
        let pauseGap = TranscriptionGap.pause(at: session.recordingDuration)
        session.transcriptionGaps.append(pauseGap)

        // Auto-save
        Task {
            try? await storageService.saveSession(session)
        }
    }

    /// Resume a paused session
    func resumeSession(_ session: LiveSession) async throws {
        guard session.state == .paused else { return }

        // Update pause gap end time
        if var lastGap = session.pauseGaps.last, lastGap.end == nil {
            lastGap.end = Date()
            session.pauseGaps[session.pauseGaps.count - 1] = lastGap
        }

        // Update transcription gap end time
        if var lastTranscriptGap = session.transcriptionGaps.last,
           lastTranscriptGap.reason == .paused {
            lastTranscriptGap.endTime = session.recordingDuration
            session.transcriptionGaps[session.transcriptionGaps.count - 1] = lastTranscriptGap
        }

        session.state = .recording
        session.pausedAt = nil

        try await audioCaptureService.resumeCapture()

        // Restart duration timer
        startDurationTimer(for: session)

        // Auto-save
        Task {
            try? await storageService.saveSession(session)
        }
    }

    /// Stop recording and mark session complete
    func stopSession(_ session: LiveSession) async {
        guard session.state == .recording || session.state == .paused else { return }

        resetDurationTimer()

        // Stop audio capture
        audioCaptureService.stopCapture()

        // Save assistant learnings from this session
        Task {
            await assistantService.endSession()
        }

        // Mark session complete
        session.state = .complete

        // Save final state
        try? await storageService.saveSession(session)

        if activeSession?.id == session.id {
            activeSession = nil
        }

        // Trigger naming prompt
        NotificationCenter.default.post(
            name: .sessionNeedsNaming,
            object: session.id
        )
    }

    /// Rename a session
    func renameSession(_ session: LiveSession, name: String) {
        session.name = name

        Task {
            try? await storageService.saveSession(session)
        }
    }

    /// Hand off session to Redact phase
    func handoffToRedact(_ session: LiveSession) -> String {
        guard session.state == .complete else {
            return ""
        }

        session.state = .handedOff

        // Save state change
        Task {
            try? await storageService.saveSession(session)
        }

        // Return raw transcript for Redact phase
        return session.rawTranscript
    }

    /// Delete a session and all associated data
    func deleteSession(_ session: LiveSession) async {
        print("SessionManager: [DEBUG] deleteSession called for \(session.id) (\(session.name ?? "unnamed"))")

        // Stop if active
        if activeSession?.id == session.id {
            audioCaptureService.stopCapture()
            activeSession = nil
        }

        // Clear LiveRedactor tracking for this session
        LiveRedactor.shared.clearSession(session.id)

        print("SessionManager: [DEBUG] Removing session from list (was \(sessions.count) sessions)")
        sessions.removeAll { $0.id == session.id }
        print("SessionManager: [DEBUG] Session removed (now \(sessions.count) sessions)")

        try? await storageService.deleteSession(session)
    }

    // MARK: - Recovery

    private var hasRestoredSessions = false

    /// Restore sessions from disk on app launch
    func restoreSessionsOnLaunch() async {
        // Prevent duplicate restoration (SwiftUI can call .task multiple times)
        guard !hasRestoredSessions else { return }
        hasRestoredSessions = true

        isRestoring = true
        defer { isRestoring = false }

        do {
            let restoredSessions = try await storageService.loadAllSessions()

            for session in restoredSessions {
                // Sessions that were recording when app crashed become complete
                if session.state == .recording || session.state == .paused {
                    session.state = .complete
                }
                // Only add if not already present (safety check)
                guard !sessions.contains(where: { $0.id == session.id }) else { continue }
                sessions.append(session)
            }

            // Sort by creation date (newest first)
            sessions.sort { $0.createdAt > $1.createdAt }

            if !restoredSessions.isEmpty {
                // Notify user of recovered sessions
                NotificationCenter.default.post(
                    name: .sessionsRecovered,
                    object: restoredSessions.count
                )
            }
        } catch {
            print("SessionManager: Failed to restore sessions: \(error)")
        }
    }

    // MARK: - Transcription Handlers

    private func handleTranscriptionResult(_ result: TranscriptionResult) {
        print("SessionManager: [DEBUG] Received transcription result - \(result.segments.count) segments for chunk \(result.chunkIndex)")
        print("SessionManager: [DEBUG] Looking for session \(result.sessionId) in \(sessions.count) sessions")

        guard let session = sessions.first(where: { $0.id == result.sessionId }) else {
            print("SessionManager: [DEBUG] Session NOT FOUND for id \(result.sessionId) - results will be LOST")
            return
        }
        print("SessionManager: [DEBUG] Found session '\(session.name ?? "unnamed")'")

        // Add segments to session
        session.transcriptSegments.append(contentsOf: result.segments)
        session.lastTranscriptUpdate = Date()

        print("SessionManager: Session now has \(session.transcriptSegments.count) total segments")

        // Mark chunk as processed
        for i in session.audioChunkPaths.indices {
            if session.audioChunkPaths[i].chunkIndex == result.chunkIndex {
                session.audioChunkPaths[i].isProcessed = true
            }
        }

        // Trigger incremental entity detection
        print("SessionManager: [DEBUG] Spawning LiveRedactor task for \(result.segments.count) segments")
        Task {
            print("SessionManager: [DEBUG] LiveRedactor task starting...")
            await LiveRedactor.shared.processNewSegments(for: session, segments: result.segments)
            print("SessionManager: [DEBUG] LiveRedactor task completed")
        }

        // Trigger AI assistant analysis (processes in background, analyses every 3 chunks)
        Task {
            await assistantService.processNewSegments(result.segments, for: session)
        }

        // Auto-save
        Task {
            try? await storageService.saveSession(session)
        }
    }

    private func handleTranscriptionFailure(_ failure: TranscriptionFailure) {
        guard let session = sessions.first(where: { $0.id == failure.sessionId }) else {
            return
        }

        // Find the chunk to get timing info
        let chunk = session.audioChunkPaths.first { $0.chunkIndex == failure.chunkIndex }

        // Add failure gap to transcript
        let gap = TranscriptionGap.transcriptionFailed(
            chunkIndex: failure.chunkIndex,
            startTime: chunk?.startTime ?? 0,
            endTime: chunk?.endTime ?? 0,
            error: failure.error.localizedDescription
        )
        session.transcriptionGaps.append(gap)

        // Auto-save
        Task {
            try? await storageService.saveSession(session)
        }
    }

    // MARK: - Audio Service Access

    /// Get current microphone level for UI (scaled 0-1 based on voice probability)
    var microphoneLevel: Float {
        audioCaptureService.voiceProbability
    }

    /// Get current system audio level for UI
    var systemLevel: Float {
        audioCaptureService.systemLevel
    }

    /// Whether audio capture is active
    var isCapturing: Bool {
        audioCaptureService.isCapturing
    }

    // MARK: - Audio Device Selection

    /// Available input devices
    var availableInputDevices: [AudioDevice] {
        audioCaptureService.availableInputDevices
    }

    /// Currently selected input device (nil = system default)
    var selectedInputDevice: AudioDevice? {
        audioCaptureService.selectedInputDevice
    }

    /// Refresh the list of available input devices
    func refreshInputDevices() {
        audioCaptureService.refreshInputDevices()
    }

    /// Select an input device (nil = system default)
    func selectInputDevice(_ device: AudioDevice?) {
        audioCaptureService.selectInputDevice(device)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let sessionsRecovered = Notification.Name("sessionsRecovered")
    static let sessionNeedsNaming = Notification.Name("sessionNeedsNaming")
}

// MARK: - Preview Helpers

#if DEBUG
extension SessionManager {
    /// Preview manager with sample sessions
    static var preview: SessionManager {
        let manager = SessionManager.shared
        return manager
    }
}
#endif
