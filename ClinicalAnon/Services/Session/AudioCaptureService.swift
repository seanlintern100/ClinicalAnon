//
//  AudioCaptureService.swift
//  ClinicalAnon
//
//  Purpose: Captures audio from microphone and system audio for live sessions
//  Organization: 3 Big Things
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import Combine

// MARK: - Audio Capture Error

enum AudioCaptureError: Error, LocalizedError {
    case microphonePermissionDenied
    case screenRecordingPermissionDenied
    case engineSetupFailed
    case noDisplayAvailable
    case writerSetupFailed(String)
    case captureAlreadyInProgress
    case noActiveCapture

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was denied. Please enable it in System Settings > Privacy & Security > Microphone."
        case .screenRecordingPermissionDenied:
            return "Screen recording permission was denied. Please enable it in System Settings > Privacy & Security > Screen Recording."
        case .engineSetupFailed:
            return "Failed to set up audio capture engine."
        case .noDisplayAvailable:
            return "No display available for system audio capture."
        case .writerSetupFailed(let reason):
            return "Failed to set up audio writer: \(reason)"
        case .captureAlreadyInProgress:
            return "Audio capture is already in progress."
        case .noActiveCapture:
            return "No active audio capture to stop or pause."
        }
    }
}

// MARK: - Audio Capture Service

/// Captures audio from microphone and system audio with synchronized timestamps
@MainActor
class AudioCaptureService: NSObject, ObservableObject {

    // MARK: - Configuration

    /// Duration of each audio chunk in seconds (3 minutes)
    private let chunkDuration: TimeInterval = 180

    /// Overlap between chunks for better transcription continuity (30 seconds)
    private let overlapDuration: TimeInterval = 30

    /// Sample rate for audio (WhisperKit expects 16kHz)
    private let sampleRate: Double = 16000

    /// Number of audio channels (mono)
    private let channels: AVAudioChannelCount = 1

    // MARK: - Timestamp Synchronization

    /// Shared start time for both audio streams to ensure alignment
    private var sessionStartTime: Date?

    // MARK: - Published State

    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var microphoneLevel: Float = 0
    @Published private(set) var systemLevel: Float = 0
    @Published private(set) var currentChunkIndex: Int = 0

    // MARK: - Audio Capture

    private var microphoneEngine: AVAudioEngine?
    private var systemAudioStream: SCStream?
    private var streamConfiguration: SCStreamConfiguration?
    private var levelTimer: Timer?

    // MARK: - File Writers (for system audio)

    private var systemWriter: AVAssetWriter?
    private var systemWriterInput: AVAssetWriterInput?
    private var chunkStartTime: Date?

    // MARK: - Audio Buffers

    private var systemBufferQueue = DispatchQueue(label: "com.redactor.sys-buffer", qos: .userInitiated)

    // MARK: - Session Reference

    private weak var currentSession: LiveSession?

    // MARK: - Chunk Rotation

    private var chunkRotationTimer: Timer?

    // MARK: - Public Methods

    /// Start capturing audio for a session
    func startCapture(for session: LiveSession) async throws {
        guard !isCapturing else {
            throw AudioCaptureError.captureAlreadyInProgress
        }

        currentSession = session
        currentChunkIndex = 0

        // Request permissions first
        try await requestMicrophonePermission()

        // Give the system a moment after permission is granted
        // This helps with the TCC database sync
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        print("AudioCaptureService: Permission granted, setting up capture...")

        // Capture shared start time BEFORE any stream setup
        sessionStartTime = Date()
        chunkStartTime = Date()

        // Start microphone capture FIRST (uses AVAudioRecorder)
        try setupMicrophoneCapture()

        // System audio capture disabled - ScreenCaptureKit has issues
        // TODO: Re-enable with proper voice processing / echo cancellation
        // For now, mic captures everything (including speaker audio in room)
        print("AudioCaptureService: System audio capture disabled (will implement with voice processing)")

        // Start chunk rotation timer
        startChunkRotationTimer()

        isCapturing = true
        print("AudioCaptureService: Capture started successfully")
    }

    /// Pause audio capture
    func pauseCapture() {
        guard isCapturing else { return }

        // Stop chunk rotation timer
        chunkRotationTimer?.invalidate()
        chunkRotationTimer = nil

        // Stop level timer
        levelTimer?.invalidate()
        levelTimer = nil

        // Pause the audio engine
        microphoneEngine?.pause()

        // Close current audio file
        audioFile = nil

        // Finish current chunk
        finishCurrentChunk()

        isCapturing = false
    }

    /// Resume audio capture after pause
    func resumeCapture() async throws {
        guard !isCapturing, currentSession != nil else { return }

        // Set up new chunk and restart engine
        try setupMicrophoneCapture()

        // Restart chunk rotation timer
        startChunkRotationTimer()

        isCapturing = true
    }

    /// Stop audio capture completely
    func stopCapture() {
        guard currentSession != nil else { return }

        // Stop timers
        chunkRotationTimer?.invalidate()
        chunkRotationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        // Stop and cleanup microphone engine
        if let engine = microphoneEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            print("AudioCaptureService: Stopped AVAudioEngine")
        }
        microphoneEngine = nil

        // Close audio file
        if let url = currentMicURL {
            print("AudioCaptureService: Closed audio file at \(url.path)")
        }
        audioFile = nil
        currentMicURL = nil

        // Finish current chunk (records file references)
        finishCurrentChunk()

        // Stop and cleanup system audio
        Task {
            try? await systemAudioStream?.stopCapture()
            systemAudioStream = nil
        }

        currentSession = nil
        sessionStartTime = nil
        isCapturing = false
    }

    // MARK: - Permission Handling

    private func requestMicrophonePermission() async throws {
        print("AudioCaptureService: Checking microphone permission...")
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("AudioCaptureService: Current status: \(status.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")

        switch status {
        case .authorized:
            print("AudioCaptureService: Already authorized")
            return
        case .notDetermined:
            print("AudioCaptureService: Requesting permission...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            print("AudioCaptureService: User response: \(granted ? "granted" : "denied")")
            if !granted {
                throw AudioCaptureError.microphonePermissionDenied
            }
            // Trust the boolean response - don't re-check status
            // (sandbox/signing issues can cause status check to return wrong value)
            return
        case .denied, .restricted:
            print("AudioCaptureService: Permission denied or restricted - please enable in System Settings > Privacy & Security > Microphone")
            throw AudioCaptureError.microphonePermissionDenied
        @unknown default:
            print("AudioCaptureService: Unknown permission status")
            throw AudioCaptureError.microphonePermissionDenied
        }
    }

    // MARK: - Microphone Setup with Voice Processing

    private func setupMicrophoneCapture() throws {
        print("AudioCaptureService: Setting up microphone capture with AVAudioEngine + Voice Processing...")

        guard let session = currentSession else {
            throw AudioCaptureError.engineSetupFailed
        }

        // Create the audio file URL for this chunk
        let sessionDir = SessionStorageService.sessionDirectory(for: session)
        let audioDir = sessionDir.appendingPathComponent("audio", isDirectory: true)

        // Ensure audio directory exists
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        // Use M4A format
        currentMicURL = audioDir.appendingPathComponent("mic_\(String(format: "%03d", currentChunkIndex)).m4a")

        // Remove existing file if present
        if let url = currentMicURL, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Create audio engine
        let engine = AVAudioEngine()
        microphoneEngine = engine

        let inputNode = engine.inputNode

        // Enable voice processing for echo cancellation
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            print("AudioCaptureService: Voice processing enabled (echo cancellation active)")
        } catch {
            print("AudioCaptureService: Failed to enable voice processing: \(error)")
            // Continue without voice processing
        }

        // Get the format from the input node
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("AudioCaptureService: Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")

        guard inputFormat.sampleRate > 0 else {
            print("AudioCaptureService: Invalid input format")
            throw AudioCaptureError.engineSetupFailed
        }

        // Create the audio file for writing
        guard let micURL = currentMicURL else {
            throw AudioCaptureError.engineSetupFailed
        }

        // Create audio file with AAC format
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVEncoderBitRateKey: 128000
        ]

        audioFile = try AVAudioFile(
            forWriting: micURL,
            settings: outputSettings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )

        print("AudioCaptureService: Created audio file at: \(micURL.path)")

        // Install tap on input node to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            self?.handleMicrophoneBuffer(buffer)
        }

        // Start the engine
        engine.prepare()
        try engine.start()

        print("AudioCaptureService: AVAudioEngine started with voice processing")

        // Start level metering timer
        startLevelMeteringTimer()
    }

    private var currentMicURL: URL?
    private var audioFile: AVAudioFile?

    private func handleMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        // Calculate audio level for UI meter
        if let channelData = buffer.floatChannelData?[0] {
            let frameCount = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameCount {
                sum += abs(channelData[i])
            }
            let average = sum / Float(max(frameCount, 1))
            Task { @MainActor in
                self.microphoneLevel = average
            }
        }

        // Write buffer to file
        do {
            try audioFile?.write(from: buffer)
        } catch {
            print("AudioCaptureService: Failed to write audio buffer: \(error)")
        }
    }

    private func startLevelMeteringTimer() {
        // Level metering is now done in handleMicrophoneBuffer
        // This timer is just for backup/fallback
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func updateMicrophoneLevel() {
        // Now handled in handleMicrophoneBuffer
    }

    // MARK: - System Audio Setup

    private func setupSystemAudioCapture() async throws {
        // Get available content to capture
        let content = try await SCShareableContent.current

        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayAvailable
        }

        // Create filter to exclude our own app
        let excludedApps = content.applications.filter { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        // Configure for audio only (minimize video capture)
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(sampleRate)
        config.channelCount = Int(channels)

        // Minimal video capture (required but we don't use it)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        streamConfiguration = config

        // Create and start stream
        systemAudioStream = SCStream(filter: filter, configuration: config, delegate: nil)

        try systemAudioStream?.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: systemBufferQueue
        )

        try await systemAudioStream?.startCapture()
    }

    // MARK: - Chunk Management

    private func startNewChunk() throws {
        guard let session = currentSession else { return }

        // Only set chunk start time if not already set (initial setup sets it)
        if chunkStartTime == nil {
            chunkStartTime = Date()
        }

        let sessionDir = SessionStorageService.sessionDirectory(for: session)
        let audioDir = sessionDir.appendingPathComponent("audio", isDirectory: true)

        // Ensure audio directory exists
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        // Note: Microphone chunk file is created by setupMicrophoneCapture() using AVAudioRecorder

        // Create system audio writer (if system audio capture is active)
        let sysURL = audioDir.appendingPathComponent("sys_\(String(format: "%03d", currentChunkIndex)).m4a")
        systemWriter = try createAssetWriter(url: sysURL)
        systemWriterInput = systemWriter?.inputs.first
    }

    private func finishCurrentChunk() {
        guard let session = currentSession,
              let startTime = chunkStartTime,
              let sessionStart = sessionStartTime else { return }

        let endTime = Date()
        let chunkDuration = endTime.timeIntervalSince(startTime)
        let sessionOffset = startTime.timeIntervalSince(sessionStart)
        let chunkIndex = currentChunkIndex

        // Get session directory
        let sessionDir = SessionStorageService.sessionDirectory(for: session)

        // Handle microphone chunk (recorded by AVAudioRecorder as M4A)
        let micURL = sessionDir.appendingPathComponent("audio/mic_\(String(format: "%03d", chunkIndex)).m4a")
        if FileManager.default.fileExists(atPath: micURL.path) {
            let micSize = (try? FileManager.default.attributesOfItem(atPath: micURL.path)[.size] as? Int64) ?? 0

            let micChunk = AudioChunkReference(
                stream: .microphone,
                chunkIndex: chunkIndex,
                startTime: sessionOffset,
                endTime: sessionOffset + chunkDuration,
                filePath: "audio/mic_\(String(format: "%03d", chunkIndex)).m4a",
                fileSize: micSize,
                isProcessed: false
            )
            session.audioChunkPaths.append(micChunk)
            print("AudioCaptureService: Added mic chunk \(chunkIndex), size: \(micSize) bytes")
        }

        // Finish writing system audio (if active)
        if let writer = systemWriter, let input = systemWriterInput {
            input.markAsFinished()
            writer.finishWriting { [weak self] in
                guard let self = self else { return }

                let sysURL = sessionDir.appendingPathComponent("audio/sys_\(String(format: "%03d", chunkIndex)).m4a")
                let sysSize = (try? FileManager.default.attributesOfItem(atPath: sysURL.path)[.size] as? Int64) ?? 0

                let sysChunk = AudioChunkReference(
                    stream: .system,
                    chunkIndex: chunkIndex,
                    startTime: sessionOffset,
                    endTime: sessionOffset + chunkDuration,
                    filePath: "audio/sys_\(String(format: "%03d", chunkIndex)).m4a",
                    fileSize: sysSize,
                    isProcessed: false
                )

                Task { @MainActor in
                    session.audioChunkPaths.append(sysChunk)
                    print("AudioCaptureService: Added sys chunk \(chunkIndex), size: \(sysSize) bytes")
                }
            }
        }

        // Notify that chunk is ready for transcription
        NotificationCenter.default.post(
            name: .audioChunkReady,
            object: AudioChunkReadyInfo(sessionId: session.id, chunkIndex: chunkIndex)
        )

        currentChunkIndex += 1
    }

    private func startChunkRotationTimer() {
        chunkRotationTimer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.rotateChunk()
            }
        }
    }

    private func rotateChunk() {
        guard isCapturing, let engine = microphoneEngine else { return }

        print("AudioCaptureService: Rotating to chunk \(currentChunkIndex + 1)")

        // Remove tap and close current audio file
        engine.inputNode.removeTap(onBus: 0)
        audioFile = nil

        // Finish current chunk (records references)
        finishCurrentChunk()

        // Reset chunk start time for new chunk
        chunkStartTime = Date()

        // Start new chunk
        do {
            try startNewChunk()

            // Reinstall tap and create new audio file
            guard let session = currentSession else { return }
            let sessionDir = SessionStorageService.sessionDirectory(for: session)
            let audioDir = sessionDir.appendingPathComponent("audio", isDirectory: true)
            currentMicURL = audioDir.appendingPathComponent("mic_\(String(format: "%03d", currentChunkIndex)).m4a")

            guard let micURL = currentMicURL else { return }

            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVEncoderBitRateKey: 128000
            ]

            audioFile = try AVAudioFile(
                forWriting: micURL,
                settings: outputSettings,
                commonFormat: inputFormat.commonFormat,
                interleaved: inputFormat.isInterleaved
            )

            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
                self?.handleMicrophoneBuffer(buffer)
            }

            print("AudioCaptureService: Started new chunk \(currentChunkIndex)")
        } catch {
            print("AudioCaptureService: Failed to start new chunk: \(error)")
        }
    }

    // MARK: - Asset Writer Creation

    private func createAssetWriter(url: URL) throws -> AVAssetWriter {
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(url: url, fileType: .m4a)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 128000
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        return writer
    }

    // MARK: - Buffer Handling (for AVAudioEngine - currently unused)

    private func handleMicrophoneBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime, sourceFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
        // This is only used when AVAudioEngine is active (not currently used)
        // Calculate audio level for UI meter
        if let channelData = buffer.floatChannelData?[0] {
            let frameCount = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameCount {
                sum += abs(channelData[i])
            }
            let average = sum / Float(max(frameCount, 1))
            Task { @MainActor in
                self.microphoneLevel = average
            }
        }
    }
}

// MARK: - SCStreamOutput

extension AudioCaptureService: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        // Calculate audio level
        if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            var length: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            if let data = dataPointer, length > 0 {
                let floatCount = length / MemoryLayout<Float>.size
                let floatPointer = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: floatCount)
                var sum: Float = 0
                for i in 0..<floatCount {
                    sum += abs(floatPointer[i])
                }
                let average = sum / Float(max(floatCount, 1))
                Task { @MainActor in
                    self.systemLevel = average
                }
            }
        }

        // Write to system audio file on MainActor
        Task { @MainActor in
            guard let writer = self.systemWriter,
                  let input = self.systemWriterInput,
                  writer.status == .writing,
                  input.isReadyForMoreMediaData else {
                return
            }
            input.append(sampleBuffer)
        }
    }
}

// MARK: - AVAudioPCMBuffer Extension

extension AVAudioPCMBuffer {
    /// Convert AVAudioPCMBuffer to CMSampleBuffer for AVAssetWriter
    func toCMSampleBuffer() -> CMSampleBuffer? {
        guard frameLength > 0 else { return nil }

        var format: CMFormatDescription?
        let asbd = self.format.streamDescription.pointee

        var mutableASBD = asbd
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &mutableASBD,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        )

        guard status == noErr, let formatDesc = format else { return nil }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(frameLength), timescale: CMTimeScale(self.format.sampleRate)),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )

        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: CMItemCount(frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard createStatus == noErr, let buffer = sampleBuffer else { return nil }

        // Set the audio buffer data from the PCM buffer
        let audioBufferList = self.audioBufferList
        let setStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            buffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: audioBufferList
        )

        guard setStatus == noErr else { return nil }

        return buffer
    }
}

// MARK: - Notifications

/// Info passed with audio chunk ready notification
struct AudioChunkReadyInfo {
    let sessionId: UUID
    let chunkIndex: Int
}

extension Notification.Name {
    static let audioChunkReady = Notification.Name("audioChunkReady")
}
