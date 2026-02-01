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

    // MARK: - Audio Engine

    private var microphoneEngine: AVAudioEngine?
    private var systemAudioStream: SCStream?
    private var streamConfiguration: SCStreamConfiguration?

    // MARK: - File Writers

    private var microphoneWriter: AVAssetWriter?
    private var microphoneWriterInput: AVAssetWriterInput?
    private var systemWriter: AVAssetWriter?
    private var systemWriterInput: AVAssetWriterInput?
    private var chunkStartTime: Date?

    // MARK: - Audio Buffers

    private var microphoneBufferQueue = DispatchQueue(label: "com.redactor.mic-buffer", qos: .userInitiated)
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

        // Capture shared start time BEFORE any stream setup
        sessionStartTime = Date()

        // Request permissions
        try await requestMicrophonePermission()

        // Start microphone capture
        try setupMicrophoneCapture()

        // Start system audio capture
        try await setupSystemAudioCapture()

        // Start first chunk
        try startNewChunk()

        // Start chunk rotation timer
        startChunkRotationTimer()

        isCapturing = true
    }

    /// Pause audio capture
    func pauseCapture() {
        guard isCapturing else { return }

        // Stop chunk rotation timer
        chunkRotationTimer?.invalidate()
        chunkRotationTimer = nil

        // Finish current chunk
        finishCurrentChunk()

        // Pause engines
        microphoneEngine?.pause()

        isCapturing = false
    }

    /// Resume audio capture after pause
    func resumeCapture() async throws {
        guard !isCapturing, currentSession != nil else { return }

        // Start new chunk
        try startNewChunk()

        // Resume microphone engine
        try microphoneEngine?.start()

        // Resume system audio (ScreenCaptureKit handles this automatically)

        // Restart chunk rotation timer
        startChunkRotationTimer()

        isCapturing = true
    }

    /// Stop audio capture completely
    func stopCapture() {
        guard currentSession != nil else { return }

        // Stop chunk rotation timer
        chunkRotationTimer?.invalidate()
        chunkRotationTimer = nil

        // Finish current chunk
        finishCurrentChunk()

        // Stop and cleanup microphone
        microphoneEngine?.stop()
        microphoneEngine?.inputNode.removeTap(onBus: 0)
        microphoneEngine = nil

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
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw AudioCaptureError.microphonePermissionDenied
            }
        case .denied, .restricted:
            throw AudioCaptureError.microphonePermissionDenied
        @unknown default:
            throw AudioCaptureError.microphonePermissionDenied
        }
    }

    // MARK: - Microphone Setup

    private func setupMicrophoneCapture() throws {
        microphoneEngine = AVAudioEngine()

        guard let engine = microphoneEngine else {
            throw AudioCaptureError.engineSetupFailed
        }

        let inputNode = engine.inputNode

        // Get the native format and create a conversion format
        let nativeFormat = inputNode.inputFormat(forBus: 0)

        // Create target format for 16kHz mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw AudioCaptureError.engineSetupFailed
        }

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
            self?.handleMicrophoneBuffer(buffer, time: time, sourceFormat: nativeFormat, targetFormat: targetFormat)
        }

        try engine.start()
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

        chunkStartTime = Date()

        let sessionDir = SessionStorageService.sessionDirectory(for: session)
        let audioDir = sessionDir.appendingPathComponent("audio", isDirectory: true)

        // Ensure audio directory exists
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        // Create microphone writer
        let micURL = audioDir.appendingPathComponent("mic_\(String(format: "%03d", currentChunkIndex)).m4a")
        microphoneWriter = try createAssetWriter(url: micURL)
        microphoneWriterInput = microphoneWriter?.inputs.first

        // Create system audio writer
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

        // Finish writing microphone
        microphoneWriterInput?.markAsFinished()
        microphoneWriter?.finishWriting { [weak self] in
            guard let self = self else { return }

            // Get file size
            let sessionDir = SessionStorageService.sessionDirectory(for: session)
            let micURL = sessionDir.appendingPathComponent("audio/mic_\(String(format: "%03d", self.currentChunkIndex)).m4a")
            let micSize = (try? FileManager.default.attributesOfItem(atPath: micURL.path)[.size] as? Int64) ?? 0

            // Create chunk reference
            let micChunk = AudioChunkReference(
                stream: .microphone,
                chunkIndex: self.currentChunkIndex,
                startTime: sessionOffset,
                endTime: sessionOffset + chunkDuration,
                filePath: "audio/mic_\(String(format: "%03d", self.currentChunkIndex)).m4a",
                fileSize: micSize,
                isProcessed: false
            )

            Task { @MainActor in
                session.audioChunkPaths.append(micChunk)
            }
        }

        // Finish writing system audio
        systemWriterInput?.markAsFinished()
        systemWriter?.finishWriting { [weak self] in
            guard let self = self else { return }

            // Get file size
            let sessionDir = SessionStorageService.sessionDirectory(for: session)
            let sysURL = sessionDir.appendingPathComponent("audio/sys_\(String(format: "%03d", self.currentChunkIndex)).m4a")
            let sysSize = (try? FileManager.default.attributesOfItem(atPath: sysURL.path)[.size] as? Int64) ?? 0

            // Create chunk reference
            let sysChunk = AudioChunkReference(
                stream: .system,
                chunkIndex: self.currentChunkIndex,
                startTime: sessionOffset,
                endTime: sessionOffset + chunkDuration,
                filePath: "audio/sys_\(String(format: "%03d", self.currentChunkIndex)).m4a",
                fileSize: sysSize,
                isProcessed: false
            )

            Task { @MainActor in
                session.audioChunkPaths.append(sysChunk)

                // Notify that chunk is ready for transcription
                NotificationCenter.default.post(
                    name: .audioChunkReady,
                    object: AudioChunkReadyInfo(sessionId: session.id, chunkIndex: self.currentChunkIndex)
                )
            }
        }

        // Update session duration
        Task { @MainActor in
            session.recordingDuration += chunkDuration
        }

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
        guard isCapturing else { return }

        finishCurrentChunk()

        do {
            try startNewChunk()
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

    // MARK: - Buffer Handling

    private func handleMicrophoneBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime, sourceFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
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

        // Convert buffer to CMSampleBuffer and write on MainActor
        guard let sampleBuffer = buffer.toCMSampleBuffer() else { return }

        Task { @MainActor in
            self.writeSampleBufferToMicrophone(sampleBuffer)
        }
    }

    private func writeSampleBufferToMicrophone(_ sampleBuffer: CMSampleBuffer) {
        guard let writer = microphoneWriter,
              let input = microphoneWriterInput,
              writer.status == .writing,
              input.isReadyForMoreMediaData else {
            return
        }

        input.append(sampleBuffer)
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
