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
import AVFoundation

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

    private var processingQueue: [(sessionId: UUID, chunkIndex: Int, chunkStartTime: TimeInterval, micPath: URL, sysPath: URL, hasMultipleParticipants: Bool)] = []
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
            print("TranscriptionService: Queuing chunk \(info.chunkIndex) for session \(info.sessionId) (startTime: \(info.chunkStartTime)s, multipleParticipants: \(info.hasMultipleParticipants))")
            Task { @MainActor in
                self?.queueChunkForProcessing(sessionId: info.sessionId, chunkIndex: info.chunkIndex, chunkStartTime: info.chunkStartTime, hasMultipleParticipants: info.hasMultipleParticipants)
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

        defer { isLoading = false }  // Always reset on exit

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
    private func queueChunkForProcessing(sessionId: UUID, chunkIndex: Int, chunkStartTime: TimeInterval, hasMultipleParticipants: Bool) {
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
        processingQueue.append((sessionId: sessionId, chunkIndex: chunkIndex, chunkStartTime: chunkStartTime, micPath: micPath, sysPath: sysPath, hasMultipleParticipants: hasMultipleParticipants))

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
                    print("TranscriptionService: Processing chunk \(item.chunkIndex) for session \(item.sessionId) (startTime: \(item.chunkStartTime)s, multipleParticipants: \(item.hasMultipleParticipants))")
                    let chunkStart = CFAbsoluteTimeGetCurrent()
                    let segments = try await transcribeChunk(
                        sessionId: item.sessionId,
                        chunkIndex: item.chunkIndex,
                        chunkStartTime: item.chunkStartTime,
                        microphonePath: item.micPath,
                        systemAudioPath: item.sysPath,
                        hasMultipleParticipants: item.hasMultipleParticipants
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
        systemAudioPath: URL,
        hasMultipleParticipants: Bool = false
    ) async throws -> [TranscriptSegment] {
        guard isModelLoaded, let whisper = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        var allSegments: [TranscriptSegment] = []
        var tempFilesToClean: [URL] = []
        defer {
            for tempURL in tempFilesToClean {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        // Update progress
        currentProgress = TranscriptionProgress(
            sessionId: sessionId,
            chunkIndex: chunkIndex,
            progress: 0,
            stage: .loading
        )

        currentProgress = TranscriptionProgress(
            sessionId: sessionId,
            chunkIndex: chunkIndex,
            progress: 0.1,
            stage: .processing
        )

        // Decrypt system audio first — needed for both transcription AND mic gating
        var decryptedSysPath: URL?
        let sysExists = FileManager.default.fileExists(atPath: systemAudioPath.path)
        let sysFileSize = sysExists ? ((try? FileManager.default.attributesOfItem(atPath: systemAudioPath.path)[.size] as? Int64) ?? 0) : 0
        let sysHasContent = sysExists && sysFileSize > 1000

        if sysHasContent {
            do {
                let path = try SessionEncryptionService.shared.decryptFileToTemp(at: systemAudioPath, for: sessionId)
                if path != systemAudioPath { tempFilesToClean.append(path) }
                decryptedSysPath = path
            } catch {
                print("TranscriptionService: System audio decryption failed (non-fatal): \(error)")
            }
        }

        // Process microphone audio (clinician)
        if FileManager.default.fileExists(atPath: microphonePath.path) {
            // Decrypt mic audio
            var decryptedMicPath = try SessionEncryptionService.shared.decryptFileToTemp(at: microphonePath, for: sessionId)
            if decryptedMicPath != microphonePath {
                tempFilesToClean.append(decryptedMicPath)
            }

            // Diarize raw mic BEFORE gating — gated audio has silence gaps that confuse
            // the speaker detector. Diarization needs continuous speech context.
            var micSpeakerSegments: [SpeakerSegment]?
            if SpeakerDiarizationService.isEnabled && hasMultipleParticipants {
                micSpeakerSegments = await applyMicDiarization(
                    audioPath: decryptedMicPath,
                    chunkStartTime: chunkStartTime
                )
            }

            // Post-capture gate: use system audio energy to silence mic during client speech.
            // Both files are from the same 60s chunk with matched timing — no latency mismatch.
            if let sysPath = decryptedSysPath {
                let gatedPath = decryptedMicPath.deletingLastPathComponent()
                    .appendingPathComponent("gated_\(decryptedMicPath.lastPathComponent)")
                if applyPostCaptureGate(micPath: decryptedMicPath, sysPath: sysPath, outputPath: gatedPath) {
                    tempFilesToClean.append(gatedPath)
                    decryptedMicPath = gatedPath
                }
            }

            var micSegments = try await transcribeFile(
                whisper: whisper,
                audioPath: decryptedMicPath,
                speaker: .clinician,
                chunkIndex: chunkIndex,
                chunkStartTime: chunkStartTime
            )

            // Merge mic diarization results (assign speakerIds to clinician segments)
            if let speakerSegs = micSpeakerSegments {
                let diarizationService = SpeakerDiarizationService.shared
                micSegments = diarizationService.mergeWithTranscript(
                    transcriptSegments: micSegments,
                    speakerSegments: speakerSegs
                )
                let uniqueSpeakers = Set(micSegments.compactMap { $0.speakerId })
                if uniqueSpeakers.count > 1 {
                    print("TranscriptionService: Mic diarization identified \(uniqueSpeakers.count) distinct speakers")
                }
            }

            allSegments.append(contentsOf: micSegments)
        }

        currentProgress = TranscriptionProgress(
            sessionId: sessionId,
            chunkIndex: chunkIndex,
            progress: 0.5,
            stage: .processing
        )

        // Process system audio (other participants)
        if let sysPath = decryptedSysPath {
            do {
                var sysSegments = try await transcribeFile(
                    whisper: whisper,
                    audioPath: sysPath,
                    speaker: .other,
                    chunkIndex: chunkIndex,
                    chunkStartTime: chunkStartTime
                )

                // Apply speaker diarization if enabled AND session has multiple participants
                if SpeakerDiarizationService.isEnabled && hasMultipleParticipants {
                    sysSegments = await applySpeakerDiarization(
                        segments: sysSegments,
                        audioPath: sysPath,
                        chunkStartTime: chunkStartTime
                    )
                }

                allSegments.append(contentsOf: sysSegments)
            } catch {
                print("TranscriptionService: System audio transcription failed (non-fatal): \(error)")
            }
        } else if sysHasContent {
            print("TranscriptionService: System audio file has content but decryption failed, skipping")
        } else if sysExists {
            print("TranscriptionService: System audio file is empty, skipping")
        }

        // Sort by start time
        allSegments.sort { $0.startTime < $1.startTime }

        // Remove echo: mic segments that are actually client speech picked up through speakers
        allSegments = removeEchoSegments(allSegments)

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

        // VAD pre-filtering: Skip transcription if audio doesn't contain speech
        if isVADEnabled {
            let containsSpeech = audioContainsSpeech(at: audioPath, sensitivity: vadSensitivity)
            if !containsSpeech {
                print("TranscriptionService: [VAD] Skipping transcription for \(speaker.label) at \(audioPath.lastPathComponent) - no speech detected")
                return []  // Return empty - timestamps preserved at chunk level
            }
        }

        do {
            // Configure decoding options to reduce hallucinations from noise
            let decodingOptions = DecodingOptions(
                task: .transcribe,
                language: "en",
                temperature: 0.0,                      // Greedy decoding for consistency
                suppressBlank: true,                   // Prevent blank token hallucinations
                compressionRatioThreshold: 2.0,        // Default 2.4 — stricter catches repetitive hallucinations
                logProbThreshold: -0.8,                // Default -1.0 — stricter confidence requirement
                noSpeechThreshold: 0.5                 // Default 0.6 — more sensitive to silence
            )

            // Transcribe with WhisperKit
            print("TranscriptionService: [DEBUG] Starting whisper.transcribe() for \(speaker.label) at \(audioPath.lastPathComponent)")
            let transcribeStart = CFAbsoluteTimeGetCurrent()
            let results = try await whisper.transcribe(audioPath: audioPath.path, decodeOptions: decodingOptions)
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
                    // Note: Whisper may output these with spaces inside brackets: [ Silence ]
                    cleanText = cleanText.replacingOccurrences(
                        of: #"\[\s*inaudible\s*\]"#,
                        with: "",
                        options: [.regularExpression, .caseInsensitive]
                    )
                    cleanText = cleanText.replacingOccurrences(
                        of: #"\[\s*no audio\s*\]"#,
                        with: "",
                        options: [.regularExpression, .caseInsensitive]
                    )
                    cleanText = cleanText.replacingOccurrences(
                        of: #"\[\s*silence\s*\]"#,
                        with: "",
                        options: [.regularExpression, .caseInsensitive]
                    )

                    // Additional Whisper hallucination patterns
                    let hallucinationPatterns = [
                        #"\[\s*unintelligible\s*\]"#,
                        #"\[\s*crosstalk\s*\]"#,
                        #"\[\s*background\s*(noise)?\s*\]"#,
                        #"\[\s*pause\s*\]"#,
                        #"\[\s*applause\s*\]"#,
                        #"\[\s*laughter\s*\]"#,
                        #"^\s*(um\s*)+$"#,           // Only "um" repeated
                        #"^\s*(uh\s*)+$"#,           // Only "uh" repeated
                        #"^\s*\.+\s*$"#,             // Only dots/ellipsis
                        #"^\s*>+\s*$"#,              // Only >> markers
                        #"^\s*-+\s*$"#,              // Only dashes
                    ]
                    for pattern in hallucinationPatterns {
                        cleanText = cleanText.replacingOccurrences(
                            of: pattern,
                            with: "",
                            options: [.regularExpression, .caseInsensitive]
                        )
                    }

                    // Clean up whitespace
                    cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Skip empty or whitespace-only segments
                    guard !cleanText.isEmpty else { continue }

                    // MARK: - Hallucination Filtering

                    // Filter 1: Minimum duration for short segments
                    // Very short bursts (< 0.3s) with minimal text are likely noise hallucinations
                    let segmentDuration = segment.end - segment.start
                    if segmentDuration < 0.3 && cleanText.count < 15 {
                        print("TranscriptionService: [HALLUCINATION] Skipping short segment (\(String(format: "%.2f", segmentDuration))s, \(cleanText.count) chars): \(cleanText)")
                        continue
                    }

                    // Filter 2: Repetition detection (Whisper often loops on noise)
                    if hasExcessiveRepetition(cleanText) {
                        print("TranscriptionService: [HALLUCINATION] Skipping repetitive segment: \(cleanText.prefix(50))...")
                        continue
                    }

                    // Filter 3: Low-confidence segments (likely Whisper hallucinations)
                    // avgLogprob typically ranges -0.1 (high confidence) to -1.0+ (low confidence)
                    let confidenceThreshold: Float = -0.7
                    if segment.avgLogprob < confidenceThreshold {
                        print("TranscriptionService: [HALLUCINATION] Skipping low-confidence segment (avgLogprob=\(String(format: "%.2f", segment.avgLogprob))): \(cleanText.prefix(50))...")
                        continue
                    }

                    // Filter 4: Borderline confidence requires minimum text length
                    let borderlineThreshold: Float = -0.5
                    if segment.avgLogprob < borderlineThreshold && cleanText.count < 10 {
                        print("TranscriptionService: [HALLUCINATION] Skipping short low-confidence segment: \(cleanText)")
                        continue
                    }

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

    // MARK: - VAD Settings

    /// Check if VAD is enabled in settings
    private var isVADEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.vadEnabled)
    }

    /// VAD sensitivity threshold (0.0-1.0)
    /// Lower values = more sensitive (more speech detected)
    private var vadSensitivity: Float {
        let saved = UserDefaults.standard.float(forKey: SettingsKeys.vadSensitivity)
        return saved > 0 ? saved : 0.5  // Default 0.5
    }

    // MARK: - Overlap Detection

    private let overlapDetector = OverlapDetector()

    /// Detect and annotate overlapping speech in segments
    /// - Parameter segments: Segments from transcription
    /// - Returns: Segments with overlap annotations
    // MARK: - Post-Capture Audio Gate

    /// Gate mic audio using system audio energy — silences mic during client speech.
    /// Both files are from the same 60s chunk so timing is perfectly aligned.
    /// Returns true if gated file was written successfully.
    private func applyPostCaptureGate(micPath: URL, sysPath: URL, outputPath: URL) -> Bool {
        do {
            // Load system audio to build energy timeline
            let sysFile = try AVAudioFile(forReading: sysPath)
            let sysFormat = sysFile.processingFormat
            let sysFrameCount = AVAudioFrameCount(sysFile.length)
            guard sysFrameCount > 0 else { return false }

            let sysBuffer = AVAudioPCMBuffer(pcmFormat: sysFormat, frameCapacity: sysFrameCount)!
            try sysFile.read(into: sysBuffer)
            guard let sysData = sysBuffer.floatChannelData?[0] else { return false }

            let sysSampleRate = sysFormat.sampleRate
            let frameSizeMs: Double = 10.0  // 10ms frames
            let frameSamples = Int(sysSampleRate * frameSizeMs / 1000.0)
            let totalFrames = Int(sysFrameCount) / frameSamples

            // Build energy timeline: true = client speaking (gate mic)
            // Use adaptive threshold: 3x the noise floor of the quietest 20% of frames
            var frameEnergies: [Float] = []
            for f in 0..<totalFrames {
                let offset = f * frameSamples
                var energy: Float = 0
                for i in 0..<frameSamples {
                    let s = sysData[offset + i]
                    energy += s * s
                }
                energy = sqrtf(energy / Float(frameSamples))
                frameEnergies.append(energy)
            }

            // Adaptive threshold: sort energies, take 20th percentile as noise floor
            let sorted = frameEnergies.sorted()
            let noiseFloorIdx = max(0, Int(Double(sorted.count) * 0.2) - 1)
            let noiseFloor = sorted.isEmpty ? Float(0.003) : sorted[noiseFloorIdx]
            let gateThreshold = max(noiseFloor * 3.0, 0.002)  // At least 0.002 to avoid gating on silence

            var gateTimeline = [Bool](repeating: false, count: totalFrames)
            for f in 0..<totalFrames {
                gateTimeline[f] = frameEnergies[f] > gateThreshold
            }

            // Smooth the gate: fill small gaps (< 200ms) to avoid choppy gating
            let minGapFrames = Int(200.0 / frameSizeMs)  // 20 frames = 200ms
            for f in 0..<totalFrames {
                if !gateTimeline[f] {
                    // Check if this is a small gap between active regions
                    let lookBack = max(0, f - minGapFrames)
                    let lookAhead = min(totalFrames - 1, f + minGapFrames)
                    let hasActiveBefore = lookBack < f && (lookBack..<f).contains { gateTimeline[$0] }
                    let hasActiveAfter = f + 1 <= lookAhead && ((f+1)...lookAhead).contains { gateTimeline[$0] }
                    if hasActiveBefore && hasActiveAfter {
                        gateTimeline[f] = true  // Fill the gap
                    }
                }
            }

            // Count gated frames for logging
            let gatedFrameCount = gateTimeline.filter { $0 }.count
            let gatedPercent = totalFrames > 0 ? Float(gatedFrameCount) / Float(totalFrames) * 100 : 0

            #if DEBUG
            print("TranscriptionService: [GATE] threshold=\(String(format: "%.4f", gateThreshold)) noise_floor=\(String(format: "%.4f", noiseFloor)) gated=\(String(format: "%.0f%%", gatedPercent)) of \(totalFrames) frames")
            #endif

            // Now load mic audio and apply gate
            let micFile = try AVAudioFile(forReading: micPath)
            let micFormat = micFile.processingFormat
            let micFrameCount = AVAudioFrameCount(micFile.length)
            guard micFrameCount > 0 else { return false }

            let micBuffer = AVAudioPCMBuffer(pcmFormat: micFormat, frameCapacity: micFrameCount)!
            try micFile.read(into: micBuffer)
            guard let micData = micBuffer.floatChannelData?[0] else { return false }

            let micSampleRate = micFormat.sampleRate

            // Apply gate: zero mic samples where system audio is active
            // Map mic samples to system audio timeline (may have different sample rates)
            let timeRatio = sysSampleRate / micSampleRate
            let fadeSamples = Int(micSampleRate * 0.02)  // 20ms fade for smooth transitions

            for i in 0..<Int(micFrameCount) {
                // Map mic sample index to system audio frame index
                let sysTimeSeconds = Double(i) / micSampleRate
                let sysFrameIdx = Int(sysTimeSeconds / frameSizeMs * 1000.0)

                if sysFrameIdx < totalFrames && gateTimeline[sysFrameIdx] {
                    micData[i] = 0  // Silence mic during client speech
                }
            }

            // Write gated mic audio
            let outputFile = try AVAudioFile(forWriting: outputPath, settings: micFile.fileFormat.settings)
            try outputFile.write(from: micBuffer)

            return true
        } catch {
            print("TranscriptionService: [GATE] Failed to apply post-capture gate: \(error)")
            return false
        }
    }

    // MARK: - Echo Removal

    /// Remove clinician segments that are actually echo of client speech picked up by the mic.
    ///
    /// Strategy: If a clinician segment overlaps in time with a system audio segment, the mic
    /// segment is almost certainly echo — the therapist can't be saying something at the exact
    /// same moment the client is speaking through the system audio. We use time overlap as the
    /// primary signal, with text similarity as a secondary confirmation for edge cases.
    private func removeEchoSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        let clinicianSegments = segments.filter { $0.speaker == .clinician }
        let otherSegments = segments.filter { $0.speaker == .other }

        guard !clinicianSegments.isEmpty && !otherSegments.isEmpty else { return segments }

        var echoIds = Set<UUID>()

        for mic in clinicianSegments {
            let micMid = (mic.startTime + mic.endTime) / 2.0

            // Simple check: is the midpoint of this clinician segment within any
            // system audio segment's time window? If yes, the client was speaking
            // at this time so the mic content is echo.
            // Use a tight 0.5s buffer to avoid clipping at speaker transitions.
            let isEcho = otherSegments.contains { sys in
                micMid >= sys.startTime + 0.5 && micMid <= sys.endTime - 0.5
            }

            if isEcho {
                echoIds.insert(mic.id)
                #if DEBUG
                print("TranscriptionService: [ECHO] Dropping clinician segment (midpoint in sys audio): \"\(mic.text.prefix(60))\"")
                #endif
            }
        }

        if !echoIds.isEmpty {
            print("TranscriptionService: [ECHO] Removed \(echoIds.count)/\(clinicianSegments.count) clinician segments (echo from system audio)")
        }

        return segments.filter { !echoIds.contains($0.id) }
    }

    func annotateOverlaps(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        return overlapDetector.annotateOverlaps(segments: segments)
    }

    // MARK: - Speaker Diarization

    /// Apply speaker diarization to identify multiple speakers in system audio
    /// - Parameters:
    ///   - segments: Transcript segments from system audio (speaker = .other)
    ///   - audioPath: Path to the system audio file
    ///   - chunkStartTime: Global start time of this chunk (for timestamp alignment)
    /// - Returns: Segments with speaker IDs assigned based on voice analysis
    private func applySpeakerDiarization(
        segments: [TranscriptSegment],
        audioPath: URL,
        chunkStartTime: TimeInterval
    ) async -> [TranscriptSegment] {
        do {
            let diarizationService = SpeakerDiarizationService.shared
            let speakerSegments = try await diarizationService.diarize(audioURL: audioPath)

            // Offset diarization timestamps to global session time
            // Diarization returns chunk-relative timestamps (0-60s), but transcript has global timestamps
#if DEBUG
            print("TranscriptionService: [DIARIZATION] Offsetting \(speakerSegments.count) diarization segments by chunkStartTime=\(String(format: "%.2f", chunkStartTime))s")
#endif
            let offsetSegments = speakerSegments.map { segment in
                SpeakerSegment(
                    speakerId: segment.speakerId,
                    startTime: segment.startTime + chunkStartTime,
                    endTime: segment.endTime + chunkStartTime,
                    confidence: segment.confidence,
                    embedding: segment.embedding
                )
            }

            // Merge diarization results with transcript
            let enhancedSegments = diarizationService.mergeWithTranscript(
                transcriptSegments: segments,
                speakerSegments: offsetSegments
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

    /// Diarize mic audio to identify multiple in-room speakers (therapist + supervisor).
    /// Returns speaker segments with global timestamps, or nil if diarization fails.
    private func applyMicDiarization(
        audioPath: URL,
        chunkStartTime: TimeInterval
    ) async -> [SpeakerSegment]? {
        do {
            let diarizationService = SpeakerDiarizationService.shared
            let speakerSegments = try await diarizationService.diarize(audioURL: audioPath)

            // Offset to global session time
            let offsetSegments = speakerSegments.map { segment in
                SpeakerSegment(
                    speakerId: segment.speakerId,
                    startTime: segment.startTime + chunkStartTime,
                    endTime: segment.endTime + chunkStartTime,
                    confidence: segment.confidence,
                    embedding: segment.embedding
                )
            }

            #if DEBUG
            let uniqueSpeakers = Set(offsetSegments.map { $0.speakerId })
            print("TranscriptionService: [MIC DIARIZATION] Found \(uniqueSpeakers.count) speaker(s) in mic audio")
            #endif

            return offsetSegments
        } catch {
            print("TranscriptionService: Mic diarization failed (non-fatal): \(error)")
            return nil
        }
    }

    // MARK: - Voice Activity Detection

    /// Analyze audio file for speech presence
    /// - Parameters:
    ///   - audioPath: Path to the audio file
    ///   - sensitivity: Threshold for speech detection (0.0-1.0, lower = more sensitive)
    /// - Returns: True if the audio contains speech above the threshold
    private func audioContainsSpeech(at audioPath: URL, sensitivity: Float = 0.5) -> Bool {
        do {
            let audioFile = try AVAudioFile(forReading: audioPath)
            let format = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)

            // Don't process very short files (< 0.1 seconds)
            guard frameCount > 0, audioFile.length > Int64(format.sampleRate * 0.1) else {
                return false
            }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                print("TranscriptionService: VAD - Could not create buffer")
                return true  // Fail open - transcribe if we can't analyze
            }

            try audioFile.read(into: buffer)

            guard let channelData = buffer.floatChannelData else {
                print("TranscriptionService: VAD - Could not get channel data")
                return true  // Fail open
            }

            // Calculate RMS energy across the audio
            let samples = channelData[0]
            let sampleCount = Int(buffer.frameLength)

            var totalEnergy: Float = 0.0
            var peakEnergy: Float = 0.0
            var speechFrameCount = 0

            // Process in frames (10ms windows for speech detection)
            let frameSize = Int(format.sampleRate * 0.01)  // 10ms frame
            let frameCount_int = sampleCount / frameSize

            // Energy threshold based on sensitivity
            // sensitivity 0.0 -> threshold ~0.001 (very sensitive)
            // sensitivity 0.5 -> threshold ~0.01
            // sensitivity 1.0 -> threshold ~0.1 (strict)
            let energyThreshold = pow(10, -3 + sensitivity * 2)  // 0.001 to 0.1 range

            // Track consecutive speech frames to filter transient noise spikes (typing, clicks)
            var maxConsecutiveSpeechFrames = 0
            var currentConsecutive = 0

            for frameIdx in 0..<frameCount_int {
                let startSample = frameIdx * frameSize
                var frameEnergy: Float = 0.0

                for i in 0..<frameSize {
                    let sample = samples[startSample + i]
                    frameEnergy += sample * sample
                }

                let rms = sqrt(frameEnergy / Float(frameSize))
                totalEnergy += rms
                peakEnergy = max(peakEnergy, rms)

                // Count frames with speech-level energy and track consecutive runs
                if rms > energyThreshold {
                    speechFrameCount += 1
                    currentConsecutive += 1
                    maxConsecutiveSpeechFrames = max(maxConsecutiveSpeechFrames, currentConsecutive)
                } else {
                    currentConsecutive = 0
                }
            }

            guard frameCount_int > 0 else {
                return false
            }

            let avgEnergy = totalEnergy / Float(frameCount_int)
            let speechRatio = Float(speechFrameCount) / Float(frameCount_int)

            // Require at least 15% of frames to have speech-level energy (was 5%)
            // AND average energy above a minimum threshold
            // AND at least 50ms of consecutive speech (5 frames at 10ms each)
            let minSpeechRatio: Float = 0.15
            let minAvgEnergy = energyThreshold * 0.5
            let minConsecutiveFrames = 5  // 50ms sustained energy

            let hasConsecutiveSpeech = maxConsecutiveSpeechFrames >= minConsecutiveFrames
            let hasSpeech = speechRatio >= minSpeechRatio && avgEnergy >= minAvgEnergy && hasConsecutiveSpeech

            #if DEBUG
            print("TranscriptionService: VAD analysis - avgEnergy=\(String(format: "%.4f", avgEnergy)), peakEnergy=\(String(format: "%.4f", peakEnergy)), speechRatio=\(String(format: "%.2f", speechRatio)), threshold=\(String(format: "%.4f", energyThreshold)), hasSpeech=\(hasSpeech)")
            #endif

            return hasSpeech
        } catch {
            print("TranscriptionService: VAD analysis failed: \(error)")
            return true  // Fail open - transcribe if we can't analyze
        }
    }

    // MARK: - Repetition Detection

    /// Detect excessive repetition in text (common Whisper hallucination pattern)
    /// Returns true if text contains 3+ consecutive identical words or repeated 2-word phrases
    private func hasExcessiveRepetition(_ text: String) -> Bool {
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard words.count >= 4 else { return false }

        // Check for 3+ consecutive identical words (e.g., "Thank you. Thank you. Thank you.")
        var consecutive = 1
        for i in 1..<words.count {
            if words[i] == words[i-1] {
                consecutive += 1
                if consecutive >= 3 { return true }
            } else {
                consecutive = 1
            }
        }

        // Check for repeated 2-word phrases (e.g., "Thank you. Thank you.")
        guard words.count >= 4 else { return false }
        for i in 0...(words.count - 4) {
            let phrase1 = words[i..<(i + 2)].joined(separator: " ")
            let phrase2 = words[(i + 2)..<(i + 4)].joined(separator: " ")
            if phrase1 == phrase2 { return true }
        }

        return false
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
