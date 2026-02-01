//
//  TranscriptionService.swift
//  ClinicalAnon
//
//  Purpose: On-device transcription using WhisperKit
//  Organization: 3 Big Things
//

import Foundation
import WhisperKit
import Combine

// MARK: - Transcription Error

enum TranscriptionError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case audioFileNotFound(String)
    case invalidAudioFormat
    case processingCancelled

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded. Please wait for the model to load."
        case .modelLoadFailed(let reason):
            return "Failed to load Whisper model: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .audioFileNotFound(let path):
            return "Audio file not found at: \(path)"
        case .invalidAudioFormat:
            return "Invalid audio format. Expected M4A or WAV file."
        case .processingCancelled:
            return "Transcription was cancelled."
        }
    }
}

// MARK: - Model Size

/// Available Whisper model sizes
enum WhisperModelSize: String, CaseIterable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case large = "large-v3"

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (~75MB)"
        case .base: return "Base (~150MB)"
        case .small: return "Small (~500MB)"
        case .medium: return "Medium (~1.5GB)"
        case .large: return "Large (~3GB)"
        }
    }

    var approximateSize: Int64 {
        switch self {
        case .tiny: return 75_000_000
        case .base: return 150_000_000
        case .small: return 500_000_000
        case .medium: return 1_500_000_000
        case .large: return 3_000_000_000
        }
    }
}

// MARK: - Transcription Progress

/// Progress information for transcription
struct TranscriptionProgress {
    let sessionId: UUID
    let chunkIndex: Int
    let progress: Double
    let stage: TranscriptionStage
}

enum TranscriptionStage: String {
    case loading = "Loading audio"
    case processing = "Transcribing"
    case postProcessing = "Processing results"
    case complete = "Complete"
}

// MARK: - Transcription Service

/// Handles on-device transcription using WhisperKit
@MainActor
class TranscriptionService: ObservableObject {

    // MARK: - Singleton

    static let shared = TranscriptionService()

    // MARK: - Published State

    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var currentProgress: TranscriptionProgress?
    @Published private(set) var loadedModelSize: WhisperModelSize?
    @Published var error: TranscriptionError?

    // MARK: - WhisperKit Instance

    private var whisperKit: WhisperKit?

    // MARK: - Processing Queue

    private var processingQueue: [(sessionId: UUID, chunkIndex: Int, micPath: URL, sysPath: URL)] = []
    private var isProcessingQueue = false

    // MARK: - Cancellation

    private var currentTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {
        // Listen for audio chunk ready notifications
        NotificationCenter.default.addObserver(
            forName: .audioChunkReady,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.object as? AudioChunkReadyInfo else { return }
            Task { @MainActor in
                self?.queueChunkForProcessing(sessionId: info.sessionId, chunkIndex: info.chunkIndex)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Model Management

    /// Load the Whisper model
    func loadModel(size: WhisperModelSize = .small) async throws {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            // Initialize WhisperKit with the specified model
            whisperKit = try await WhisperKit(
                model: "openai_whisper-\(size.rawValue)"
            )

            isModelLoaded = true
            loadedModelSize = size
        } catch {
            self.error = .modelLoadFailed(error.localizedDescription)
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }

        isLoading = false
    }

    /// Unload the model to free memory
    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
        loadedModelSize = nil
    }

    /// Check if model is available (downloaded)
    func isModelAvailable(size: WhisperModelSize) -> Bool {
        // WhisperKit downloads models on first use
        // Check if model files exist in the cache
        let modelName = "openai_whisper-\(size.rawValue)"
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        let modelPath = documentsPath.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(modelName)")
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    // MARK: - Queue Management

    /// Queue a chunk for transcription processing
    private func queueChunkForProcessing(sessionId: UUID, chunkIndex: Int) {
        // Get session and audio paths
        let sessionDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Redactor/Sessions/\(sessionId.uuidString)")
        let audioDir = sessionDir.appendingPathComponent("audio")

        let micPath = audioDir.appendingPathComponent("mic_\(String(format: "%03d", chunkIndex)).m4a")
        let sysPath = audioDir.appendingPathComponent("sys_\(String(format: "%03d", chunkIndex)).m4a")

        // Add to queue
        processingQueue.append((sessionId: sessionId, chunkIndex: chunkIndex, micPath: micPath, sysPath: sysPath))

        // Start processing if not already running
        processNextInQueue()
    }

    /// Process the next item in the queue
    private func processNextInQueue() {
        guard !isProcessingQueue, !processingQueue.isEmpty else { return }

        isProcessingQueue = true

        currentTask = Task {
            while !processingQueue.isEmpty {
                let item = processingQueue.removeFirst()

                do {
                    let segments = try await transcribeChunk(
                        sessionId: item.sessionId,
                        chunkIndex: item.chunkIndex,
                        microphonePath: item.micPath,
                        systemAudioPath: item.sysPath
                    )

                    // Notify with results
                    NotificationCenter.default.post(
                        name: .transcriptionComplete,
                        object: TranscriptionResult(
                            sessionId: item.sessionId,
                            chunkIndex: item.chunkIndex,
                            segments: segments
                        )
                    )
                } catch {
                    // Post failure notification
                    NotificationCenter.default.post(
                        name: .transcriptionFailed,
                        object: TranscriptionFailure(
                            sessionId: item.sessionId,
                            chunkIndex: item.chunkIndex,
                            error: error
                        )
                    )
                }
            }

            isProcessingQueue = false
        }
    }

    // MARK: - Transcription

    /// Transcribe a chunk of audio
    func transcribeChunk(
        sessionId: UUID,
        chunkIndex: Int,
        microphonePath: URL,
        systemAudioPath: URL
    ) async throws -> [TranscriptSegment] {
        guard isModelLoaded, let whisper = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        var allSegments: [TranscriptSegment] = []

        // Update progress
        currentProgress = TranscriptionProgress(
            sessionId: sessionId,
            chunkIndex: chunkIndex,
            progress: 0,
            stage: .loading
        )

        // Process microphone audio (clinician)
        if FileManager.default.fileExists(atPath: microphonePath.path) {
            currentProgress = TranscriptionProgress(
                sessionId: sessionId,
                chunkIndex: chunkIndex,
                progress: 0.1,
                stage: .processing
            )

            let micSegments = try await transcribeFile(
                whisper: whisper,
                audioPath: microphonePath,
                speaker: .clinician,
                chunkIndex: chunkIndex
            )
            allSegments.append(contentsOf: micSegments)
        }

        currentProgress = TranscriptionProgress(
            sessionId: sessionId,
            chunkIndex: chunkIndex,
            progress: 0.5,
            stage: .processing
        )

        // Process system audio (other participants)
        if FileManager.default.fileExists(atPath: systemAudioPath.path) {
            let sysSegments = try await transcribeFile(
                whisper: whisper,
                audioPath: systemAudioPath,
                speaker: .other,
                chunkIndex: chunkIndex
            )
            allSegments.append(contentsOf: sysSegments)
        }

        // Sort by start time
        allSegments.sort { $0.startTime < $1.startTime }

        currentProgress = TranscriptionProgress(
            sessionId: sessionId,
            chunkIndex: chunkIndex,
            progress: 1.0,
            stage: .complete
        )

        return allSegments
    }

    /// Transcribe a single audio file
    private func transcribeFile(
        whisper: WhisperKit,
        audioPath: URL,
        speaker: Speaker,
        chunkIndex: Int
    ) async throws -> [TranscriptSegment] {
        guard FileManager.default.fileExists(atPath: audioPath.path) else {
            throw TranscriptionError.audioFileNotFound(audioPath.path)
        }

        do {
            // Transcribe with WhisperKit
            let results = try await whisper.transcribe(audioPath: audioPath.path)

            // Convert WhisperKit results to TranscriptSegments
            var segments: [TranscriptSegment] = []

            for result in results {
                // WhisperKit returns segments with timing info
                let whisperSegments = result.segments
                for segment in whisperSegments {
                    let transcriptSegment = TranscriptSegment(
                        speaker: speaker,
                        text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        startTime: TimeInterval(segment.start),
                        endTime: TimeInterval(segment.end),
                        chunkIndex: chunkIndex,
                        confidence: Double(segment.avgLogprob)
                    )

                    // Only add segments with actual content
                    if !transcriptSegment.text.isEmpty {
                        segments.append(transcriptSegment)
                    }
                }
            }

            return segments
        } catch {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    // MARK: - Manual Transcription

    /// Manually transcribe a specific chunk (for retry)
    func retryTranscription(for session: LiveSession, chunkIndex: Int) async throws -> [TranscriptSegment] {
        let sessionDir = SessionStorageService.sessionDirectory(for: session)
        let audioDir = sessionDir.appendingPathComponent("audio")

        let micPath = audioDir.appendingPathComponent("mic_\(String(format: "%03d", chunkIndex)).m4a")
        let sysPath = audioDir.appendingPathComponent("sys_\(String(format: "%03d", chunkIndex)).m4a")

        return try await transcribeChunk(
            sessionId: session.id,
            chunkIndex: chunkIndex,
            microphonePath: micPath,
            systemAudioPath: sysPath
        )
    }

    // MARK: - Cancellation

    /// Cancel current processing
    func cancelProcessing() {
        currentTask?.cancel()
        currentTask = nil
        processingQueue.removeAll()
        isProcessingQueue = false
        isProcessing = false
        currentProgress = nil
    }
}

// MARK: - Notifications

struct TranscriptionResult {
    let sessionId: UUID
    let chunkIndex: Int
    let segments: [TranscriptSegment]
}

struct TranscriptionFailure {
    let sessionId: UUID
    let chunkIndex: Int
    let error: Error
}

extension Notification.Name {
    static let transcriptionComplete = Notification.Name("transcriptionComplete")
    static let transcriptionFailed = Notification.Name("transcriptionFailed")
}

// MARK: - Preview Helpers

#if DEBUG
extension TranscriptionService {
    /// Mock transcription service for previews
    static var preview: TranscriptionService {
        let service = TranscriptionService.shared
        return service
    }
}
#endif
