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
enum WhisperModelSize: String, CaseIterable, Identifiable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case large = "large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var sizeDescription: String {
        switch self {
        case .tiny: return "~75 MB"
        case .base: return "~150 MB"
        case .small: return "Bundled"
        case .medium: return "~1.5 GB"
        case .large: return "~3 GB"
        }
    }

    var isBundled: Bool {
        self == .small
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

    // MARK: - Download State

    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0
    @Published var downloadStatus: String = ""

    // MARK: - Model Selection

    var selectedModelSize: WhisperModelSize {
        get {
            let saved = UserDefaults.standard.string(forKey: SettingsKeys.whisperModelSize)
            return WhisperModelSize(rawValue: saved ?? "") ?? .medium
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: SettingsKeys.whisperModelSize)
            // Unload current model when selection changes (will reload on next use)
            if isModelLoaded && loadedModelSize != newValue {
                unloadModel()
            }
            objectWillChange.send()
        }
    }

    // MARK: - WhisperKit Instance

    private var whisperKit: WhisperKit?

    // MARK: - Processing Queue

    private var processingQueue: [(sessionId: UUID, chunkIndex: Int, chunkStartTime: TimeInterval, micPath: URL, sysPath: URL)] = []
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
            print("TranscriptionService: Received audioChunkReady notification")
            guard let info = notification.object as? AudioChunkReadyInfo else {
                print("TranscriptionService: Invalid notification object")
                return
            }
            print("TranscriptionService: Queuing chunk \(info.chunkIndex) for session \(info.sessionId) (startTime: \(info.chunkStartTime)s)")
            Task { @MainActor in
                self?.queueChunkForProcessing(sessionId: info.sessionId, chunkIndex: info.chunkIndex, chunkStartTime: info.chunkStartTime)
            }
        }
        print("TranscriptionService: Initialized and listening for audio chunks")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Model Management

    /// Load the Whisper model (uses selected model size by default)
    func loadModel(size: WhisperModelSize? = nil) async throws {
        let modelSize = size ?? selectedModelSize
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            // Initialize WhisperKit with the specified model
            whisperKit = try await WhisperKit(
                model: "openai_whisper-\(modelSize.rawValue)"
            )

            isModelLoaded = true
            loadedModelSize = modelSize
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

    /// Check if model is available (downloaded/cached)
    func isModelCached(size: WhisperModelSize) -> Bool {
        // Bundled model is always available
        if size.isBundled {
            return true
        }

        // Check if model files exist in the cache
        let modelName = "openai_whisper-\(size.rawValue)"
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        let modelPath = documentsPath.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(modelName)")
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    /// Legacy method name for compatibility
    func isModelAvailable(size: WhisperModelSize) -> Bool {
        return isModelCached(size: size)
    }

    /// Download and load a model
    func downloadModel(size: WhisperModelSize) async throws {
        guard !isDownloading && !isLoading else { return }

        isDownloading = true
        downloadProgress = -1  // Negative indicates indeterminate
        downloadStatus = "Downloading \(size.displayName) model... This may take several minutes."

        // Register with DownloadStateManager for quit protection
        DownloadStateManager.shared.startDownload()

        defer {
            isDownloading = false
            downloadProgress = 0
            downloadStatus = ""
            DownloadStateManager.shared.endDownload()
        }

        do {
            DownloadStateManager.shared.updateProgress(0.5, status: downloadStatus)

            // WhisperKit handles download automatically via initialization
            whisperKit = try await WhisperKit(
                model: "openai_whisper-\(size.rawValue)"
            )

            downloadProgress = 1.0
            downloadStatus = "Complete"
            DownloadStateManager.shared.updateProgress(1.0, status: "Complete")

            isModelLoaded = true
            loadedModelSize = size
            selectedModelSize = size
        } catch {
            self.error = .modelLoadFailed(error.localizedDescription)
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Delete a downloaded model
    func deleteModel(size: WhisperModelSize) throws {
        // Don't allow deleting bundled model
        guard !size.isBundled else { return }

        // Unload if this is the currently loaded model
        if loadedModelSize == size {
            unloadModel()
        }

        // Delete model files from cache
        let modelName = "openai_whisper-\(size.rawValue)"
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let modelPath = documentsPath.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(modelName)")

        if FileManager.default.fileExists(atPath: modelPath.path) {
            try FileManager.default.removeItem(at: modelPath)
        }
    }

    // MARK: - Queue Management

    /// Queue a chunk for transcription processing
    private func queueChunkForProcessing(sessionId: UUID, chunkIndex: Int, chunkStartTime: TimeInterval) {
        // Get session and audio paths
        let sessionDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Redactor/Sessions/\(sessionId.uuidString)")
        let audioDir = sessionDir.appendingPathComponent("audio")

        // Try WAV first (current format), fall back to M4A
        var micPath = audioDir.appendingPathComponent("mic_\(String(format: "%03d", chunkIndex)).wav")
        if !FileManager.default.fileExists(atPath: micPath.path) {
            micPath = audioDir.appendingPathComponent("mic_\(String(format: "%03d", chunkIndex)).m4a")
        }
        var sysPath = audioDir.appendingPathComponent("sys_\(String(format: "%03d", chunkIndex)).wav")
        if !FileManager.default.fileExists(atPath: sysPath.path) {
            sysPath = audioDir.appendingPathComponent("sys_\(String(format: "%03d", chunkIndex)).m4a")
        }

        // Add to queue
        processingQueue.append((sessionId: sessionId, chunkIndex: chunkIndex, chunkStartTime: chunkStartTime, micPath: micPath, sysPath: sysPath))

        // Start processing if not already running
        processNextInQueue()
    }

    /// Process the next item in the queue
    private func processNextInQueue() {
        guard !isProcessingQueue, !processingQueue.isEmpty else { return }

        isProcessingQueue = true

        currentTask = Task {
            // Load model if not already loaded
            if !isModelLoaded {
                let modelSize = selectedModelSize
                print("TranscriptionService: Loading Whisper model (\(modelSize.displayName)) for transcription...")
                do {
                    try await loadModel(size: modelSize)
                    print("TranscriptionService: Model loaded successfully")
                } catch {
                    print("TranscriptionService: Failed to load model: \(error)")
                    // Clear queue since we can't process without model
                    processingQueue.removeAll()
                    isProcessingQueue = false
                    return
                }
            }

            print("TranscriptionService: [DEBUG] Starting queue processing, \(processingQueue.count) items in queue")
            while !processingQueue.isEmpty {
                let item = processingQueue.removeFirst()
                print("TranscriptionService: [DEBUG] Queue now has \(processingQueue.count) items remaining")

                do {
                    print("TranscriptionService: Processing chunk \(item.chunkIndex) for session \(item.sessionId) (startTime: \(item.chunkStartTime)s)")
                    let chunkStart = CFAbsoluteTimeGetCurrent()
                    let segments = try await transcribeChunk(
                        sessionId: item.sessionId,
                        chunkIndex: item.chunkIndex,
                        chunkStartTime: item.chunkStartTime,
                        microphonePath: item.micPath,
                        systemAudioPath: item.sysPath
                    )

                    let chunkElapsed = CFAbsoluteTimeGetCurrent() - chunkStart
                    print("TranscriptionService: [DEBUG] Chunk \(item.chunkIndex) completed in \(String(format: "%.2f", chunkElapsed))s - \(segments.count) segments")
                    for segment in segments.prefix(3) {
                        print("TranscriptionService:   [\(segment.speaker.label)] \(segment.text.prefix(50))...")
                    }

                    // Notify with results
                    NotificationCenter.default.post(
                        name: .transcriptionComplete,
                        object: TranscriptionResult(
                            sessionId: item.sessionId,
                            chunkIndex: item.chunkIndex,
                            segments: segments
                        )
                    )
                    print("TranscriptionService: Posted transcriptionComplete notification")
                } catch {
                    print("TranscriptionService: [DEBUG] Chunk \(item.chunkIndex) FAILED: \(error)")
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

            print("TranscriptionService: [DEBUG] Queue processing complete, isProcessingQueue = false")
            isProcessingQueue = false
        }
    }

    // MARK: - Transcription

    /// Transcribe a chunk of audio
    func transcribeChunk(
        sessionId: UUID,
        chunkIndex: Int,
        chunkStartTime: TimeInterval = 0,
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
                chunkIndex: chunkIndex,
                chunkStartTime: chunkStartTime
            )
            allSegments.append(contentsOf: micSegments)
        }

        currentProgress = TranscriptionProgress(
            sessionId: sessionId,
            chunkIndex: chunkIndex,
            progress: 0.5,
            stage: .processing
        )

        // Process system audio (other participants) - only if file exists and has content
        if FileManager.default.fileExists(atPath: systemAudioPath.path) {
            // Check file size - skip if empty
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: systemAudioPath.path)[.size] as? Int64) ?? 0
            if fileSize > 1000 {  // Skip files smaller than 1KB (likely empty/headers only)
                do {
                    var sysSegments = try await transcribeFile(
                        whisper: whisper,
                        audioPath: systemAudioPath,
                        speaker: .other,
                        chunkIndex: chunkIndex,
                        chunkStartTime: chunkStartTime
                    )

                    // Apply speaker diarization if enabled (identifies multiple remote speakers)
                    if SpeakerDiarizationService.isEnabled {
                        sysSegments = await applySpeakerDiarization(
                            segments: sysSegments,
                            audioPath: systemAudioPath
                        )
                    }

                    allSegments.append(contentsOf: sysSegments)
                } catch {
                    print("TranscriptionService: System audio transcription failed (non-fatal): \(error)")
                    // Continue without system audio - mic transcript is still valid
                }
            } else {
                print("TranscriptionService: System audio file is empty, skipping")
            }
        }

        // Sort by start time
        allSegments.sort { $0.startTime < $1.startTime }

        // Detect overlapping speech between speakers
        allSegments = annotateOverlaps(allSegments)

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
        chunkIndex: Int,
        chunkStartTime: TimeInterval = 0
    ) async throws -> [TranscriptSegment] {
        guard FileManager.default.fileExists(atPath: audioPath.path) else {
            throw TranscriptionError.audioFileNotFound(audioPath.path)
        }

        do {
            // Transcribe with WhisperKit
            print("TranscriptionService: [DEBUG] Starting whisper.transcribe() for \(speaker.label) at \(audioPath.lastPathComponent)")
            let transcribeStart = CFAbsoluteTimeGetCurrent()
            let results = try await whisper.transcribe(audioPath: audioPath.path)
            let transcribeElapsed = CFAbsoluteTimeGetCurrent() - transcribeStart
            print("TranscriptionService: [DEBUG] whisper.transcribe() completed in \(String(format: "%.2f", transcribeElapsed))s - \(results.count) results")

            // Convert WhisperKit results to TranscriptSegments
            var segments: [TranscriptSegment] = []

            for result in results {
                // WhisperKit returns segments with timing info
                let whisperSegments = result.segments
                for segment in whisperSegments {
                    // Clean up Whisper tokens from text
                    var cleanText = segment.text

                    // Remove all Whisper special tokens: <|...|> patterns
                    cleanText = cleanText.replacingOccurrences(
                        of: #"<\|[^>]+\|>"#,
                        with: "",
                        options: .regularExpression
                    )

                    // Remove [BLANK_AUDIO] and similar bracketed markers that indicate no speech
                    cleanText = cleanText.replacingOccurrences(
                        of: #"\[BLANK_AUDIO\]"#,
                        with: "",
                        options: .regularExpression
                    )
                    cleanText = cleanText.replacingOccurrences(
                        of: #"\[MUSIC\]"#,
                        with: "[music]",
                        options: .regularExpression
                    )
                    // Remove [inaudible], [no audio], [silence] markers - these don't add value
                    cleanText = cleanText.replacingOccurrences(
                        of: #"\[inaudible\]"#,
                        with: "",
                        options: [.regularExpression, .caseInsensitive]
                    )
                    cleanText = cleanText.replacingOccurrences(
                        of: #"\[no audio\]"#,
                        with: "",
                        options: [.regularExpression, .caseInsensitive]
                    )
                    cleanText = cleanText.replacingOccurrences(
                        of: #"\[silence\]"#,
                        with: "",
                        options: [.regularExpression, .caseInsensitive]
                    )

                    // Clean up whitespace
                    cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Skip empty or whitespace-only segments
                    guard !cleanText.isEmpty else { continue }

                    // Add chunk start time offset to get absolute session timestamp
                    // Convert avgLogprob (negative log probability) to 0-1 probability scale
                    // avgLogprob is typically -0.1 to -1.0, where closer to 0 = higher confidence
                    let probability = exp(Double(segment.avgLogprob))

                    let transcriptSegment = TranscriptSegment(
                        speaker: speaker,
                        text: cleanText,
                        startTime: chunkStartTime + TimeInterval(segment.start),
                        endTime: chunkStartTime + TimeInterval(segment.end),
                        chunkIndex: chunkIndex,
                        confidence: probability
                    )

                    segments.append(transcriptSegment)
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

        // Try WAV first (current format), fall back to M4A
        var micPath = audioDir.appendingPathComponent("mic_\(String(format: "%03d", chunkIndex)).wav")
        if !FileManager.default.fileExists(atPath: micPath.path) {
            micPath = audioDir.appendingPathComponent("mic_\(String(format: "%03d", chunkIndex)).m4a")
        }
        var sysPath = audioDir.appendingPathComponent("sys_\(String(format: "%03d", chunkIndex)).wav")
        if !FileManager.default.fileExists(atPath: sysPath.path) {
            sysPath = audioDir.appendingPathComponent("sys_\(String(format: "%03d", chunkIndex)).m4a")
        }

        // Estimate chunk start time (chunk duration is 60 seconds)
        let chunkStartTime = TimeInterval(chunkIndex) * 60.0

        return try await transcribeChunk(
            sessionId: session.id,
            chunkIndex: chunkIndex,
            chunkStartTime: chunkStartTime,
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

    // MARK: - Overlap Detection

    private let overlapDetector = OverlapDetector()

    /// Detect and annotate overlapping speech in segments
    /// - Parameter segments: Segments from transcription
    /// - Returns: Segments with overlap annotations
    func annotateOverlaps(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        return overlapDetector.annotateOverlaps(segments: segments)
    }

    // MARK: - Speaker Diarization

    /// Apply speaker diarization to identify multiple speakers in system audio
    /// - Parameters:
    ///   - segments: Transcript segments from system audio (speaker = .other)
    ///   - audioPath: Path to the system audio file
    /// - Returns: Segments with speaker IDs assigned based on voice analysis
    private func applySpeakerDiarization(
        segments: [TranscriptSegment],
        audioPath: URL
    ) async -> [TranscriptSegment] {
        do {
            let diarizationService = SpeakerDiarizationService.shared
            let speakerSegments = try await diarizationService.diarize(audioURL: audioPath)

            // Merge diarization results with transcript
            let enhancedSegments = diarizationService.mergeWithTranscript(
                transcriptSegments: segments,
                speakerSegments: speakerSegments
            )

            // Log results
            let uniqueSpeakers = Set(enhancedSegments.compactMap { $0.speakerId })
            if uniqueSpeakers.count > 1 {
                print("TranscriptionService: Diarization identified \(uniqueSpeakers.count) distinct speakers in system audio")
            }

            return enhancedSegments
        } catch {
            print("TranscriptionService: Speaker diarization failed (non-fatal): \(error)")
            // Return original segments if diarization fails
            return segments
        }
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
