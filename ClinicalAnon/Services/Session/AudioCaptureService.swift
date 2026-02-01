//
//  AudioCaptureService.swift
//  ClinicalAnon
//
//  Purpose: Captures audio from microphone and system audio for live sessions
//  Organization: 3 Big Things
//

import Foundation
import AVFoundation
import AudioToolbox
import CoreAudio
import ScreenCaptureKit
import Combine

// MARK: - Audio Device

/// Represents an audio input device
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    var isDefault: Bool = false

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.id == rhs.id
    }
}

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

    /// Sample rate for microphone audio (WhisperKit expects 16kHz)
    private let sampleRate: Double = 16000

    /// Sample rate for system audio (ScreenCaptureKit standard)
    private let systemSampleRate: Int = 44100

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

    // MARK: - Audio Device Selection

    @Published var availableInputDevices: [AudioDevice] = []
    @Published var selectedInputDevice: AudioDevice?

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
    private var systemAudioFrameCount: Int = 0

    // MARK: - Session Reference

    private weak var currentSession: LiveSession?

    // MARK: - Chunk Rotation

    private var chunkRotationTimer: Timer?

    // MARK: - Audio Device Enumeration

    /// Get list of available audio input devices
    static func getAudioInputDevices() -> [AudioDevice] {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Get size of device list
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        guard status == noErr else {
            print("AudioCaptureService: Failed to get device list size, status: \(status)")
            return []
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        // Get device IDs
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        guard status == noErr else {
            print("AudioCaptureService: Failed to get device list, status: \(status)")
            return []
        }

        // Get default input device
        var defaultInputDevice: AudioDeviceID = 0
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            0,
            nil,
            &defaultSize,
            &defaultInputDevice
        )

        // Filter to input devices and get names
        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            // Check if device has input channels
            var inputChannelsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var bufferListSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &inputChannelsAddress, 0, nil, &bufferListSize)
            guard status == noErr, bufferListSize > 0 else { return nil }

            let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPtr.deallocate() }

            status = AudioObjectGetPropertyData(deviceID, &inputChannelsAddress, 0, nil, &bufferListSize, bufferListPtr)
            guard status == noErr else { return nil }

            // Check if there are input channels
            let bufferList = bufferListPtr.pointee
            var hasInputChannels = false
            for i in 0..<Int(bufferList.mNumberBuffers) {
                let buffer = withUnsafePointer(to: bufferList.mBuffers) { ptr in
                    ptr.withMemoryRebound(to: AudioBuffer.self, capacity: Int(bufferList.mNumberBuffers)) { bufferPtr in
                        bufferPtr[i]
                    }
                }
                if buffer.mNumberChannels > 0 {
                    hasInputChannels = true
                    break
                }
            }
            guard hasInputChannels else { return nil }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var name: CFString?
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)
            guard status == noErr, let deviceName = name as String? else { return nil }

            return AudioDevice(
                id: deviceID,
                name: deviceName,
                isDefault: deviceID == defaultInputDevice
            )
        }
    }

    /// Refresh the list of available input devices
    func refreshInputDevices() {
        availableInputDevices = Self.getAudioInputDevices()

        // Restore selected device from UserDefaults if set
        if selectedInputDevice == nil {
            let savedDeviceID = UserDefaults.standard.integer(forKey: SettingsKeys.selectedInputDeviceID)
            if savedDeviceID != 0 {
                selectedInputDevice = availableInputDevices.first { $0.id == AudioDeviceID(savedDeviceID) }
            }
        }

        // If selected device is no longer available, reset to nil (system default)
        if let selected = selectedInputDevice,
           !availableInputDevices.contains(where: { $0.id == selected.id }) {
            selectedInputDevice = nil
        }
    }

    /// Select an input device (nil = system default)
    func selectInputDevice(_ device: AudioDevice?) {
        selectedInputDevice = device
        if let device = device {
            UserDefaults.standard.set(Int(device.id), forKey: SettingsKeys.selectedInputDeviceID)
        } else {
            UserDefaults.standard.removeObject(forKey: SettingsKeys.selectedInputDeviceID)
        }
    }

    // MARK: - Audio Device Assignment

    /// Assign specific input device to audio engine's input node
    private func assignAudioInput(inputNode: AVAudioInputNode, deviceID: AudioDeviceID) {
        guard let audioUnit = inputNode.audioUnit else {
            print("AudioCaptureService: No audio unit available for device assignment")
            return
        }

        var deviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status == noErr {
            print("AudioCaptureService: Successfully assigned input device ID: \(deviceID)")
        } else {
            print("AudioCaptureService: Failed to set input device, status: \(status)")
        }
    }

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

        // Start system audio capture for remote participants
        // With voice processing enabled on mic, this gives us clean separation
        do {
            try await setupSystemAudioCapture()
            try startNewChunk()
            print("AudioCaptureService: System audio capture started")
        } catch {
            print("AudioCaptureService: System audio capture failed (optional): \(error)")
            // Continue without system audio - mic is more important
        }

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

        // Use WAV format (more reliable with AVAudioEngine voice processing)
        currentMicURL = audioDir.appendingPathComponent("mic_\(String(format: "%03d", currentChunkIndex)).wav")

        // Remove existing file if present
        if let url = currentMicURL, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Create audio engine
        let engine = AVAudioEngine()
        microphoneEngine = engine

        let inputNode = engine.inputNode

        // Assign specific input device if selected (not using system default)
        if let device = selectedInputDevice {
            print("AudioCaptureService: Using selected input device: \(device.name) (ID: \(device.id))")
            assignAudioInput(inputNode: inputNode, deviceID: device.id)
        } else {
            print("AudioCaptureService: Using system default input device")
        }

        // Enable voice processing for echo cancellation - try to enable, fall back gracefully
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            print("AudioCaptureService: Voice processing enabled (echo cancellation active)")

            // Disable automatic ducking of system audio
            // Voice processing normally reduces system volume to help with echo cancellation
            // But we want to keep system audio at full volume since we're recording it separately
            if let audioUnit = inputNode.audioUnit {
                var duckingEnabled: UInt32 = 0  // 0 = disabled, 1 = enabled
                let propertySize = UInt32(MemoryLayout<UInt32>.size)
                // kAUVoiceIOProperty_DuckNonVoiceAudio = 2013
                let status = AudioUnitSetProperty(
                    audioUnit,
                    AudioUnitPropertyID(2013),
                    kAudioUnitScope_Global,
                    0,
                    &duckingEnabled,
                    propertySize
                )
                if status == noErr {
                    print("AudioCaptureService: Disabled automatic audio ducking")
                } else {
                    print("AudioCaptureService: Could not disable audio ducking, status: \(status)")
                }
            }
        } catch {
            print("AudioCaptureService: Voice processing unavailable for this device configuration: \(error)")
            // Continue without voice processing - recording will still work
        }

        // Get the format from the input node AFTER enabling voice processing
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("AudioCaptureService: Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels, \(inputFormat.commonFormat.rawValue)")

        guard inputFormat.sampleRate > 0 else {
            print("AudioCaptureService: Invalid input format")
            throw AudioCaptureError.engineSetupFailed
        }

        // Create the audio file for writing
        guard let micURL = currentMicURL else {
            throw AudioCaptureError.engineSetupFailed
        }

        // Create audio file in same format as input (WAV/PCM)
        // This avoids format conversion issues
        audioFile = try AVAudioFile(forWriting: micURL, settings: inputFormat.settings)

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
        print("AudioCaptureService: Setting up system audio capture...")

        // Check screen recording permission first
        // Note: ScreenCaptureKit will prompt for permission on first use
        print("AudioCaptureService: Requesting screen content access...")

        // Get available content to capture
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            print("AudioCaptureService: Got shareable content - \(content.displays.count) displays, \(content.applications.count) apps")
        } catch {
            print("AudioCaptureService: Failed to get shareable content: \(error)")
            print("AudioCaptureService: Make sure Screen Recording permission is granted in System Settings > Privacy & Security")
            throw AudioCaptureError.screenRecordingPermissionDenied
        }

        guard let display = content.displays.first else {
            print("AudioCaptureService: No display available")
            throw AudioCaptureError.noDisplayAvailable
        }

        print("AudioCaptureService: Found display: \(display.width)x\(display.height)")

        // Create filter to capture all audio except our own app
        let excludedApps = content.applications.filter { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        // Configure for audio capture
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 44100  // Standard sample rate
        config.channelCount = 1    // Mono

        // Minimal video capture (required by ScreenCaptureKit but we don't use it)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 fps minimum
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        streamConfiguration = config

        // Create stream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        systemAudioStream = stream

        // Add audio output handler
        try stream.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: systemBufferQueue
        )

        print("AudioCaptureService: Starting system audio stream...")
        print("AudioCaptureService: Stream config - capturesAudio: \(config.capturesAudio), excludesCurrentProcessAudio: \(config.excludesCurrentProcessAudio)")
        print("AudioCaptureService: Stream config - sampleRate: \(config.sampleRate), channelCount: \(config.channelCount)")
        try await stream.startCapture()
        print("AudioCaptureService: System audio stream started successfully - waiting for audio frames...")
        systemAudioFrameCount = 0
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
        systemWriter = try createAssetWriter(url: sysURL, sampleRate: systemSampleRate)
        systemWriterInput = systemWriter?.inputs.first
        systemAudioFrameCount = 0
        print("AudioCaptureService: System audio writer ready for chunk \(currentChunkIndex)")
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

        // Handle microphone chunk (recorded by AVAudioEngine as WAV)
        let micURL = sessionDir.appendingPathComponent("audio/mic_\(String(format: "%03d", chunkIndex)).wav")
        if FileManager.default.fileExists(atPath: micURL.path) {
            let micSize = (try? FileManager.default.attributesOfItem(atPath: micURL.path)[.size] as? Int64) ?? 0

            let micChunk = AudioChunkReference(
                stream: .microphone,
                chunkIndex: chunkIndex,
                startTime: sessionOffset,
                endTime: sessionOffset + chunkDuration,
                filePath: "audio/mic_\(String(format: "%03d", chunkIndex)).wav",
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
                guard self != nil else { return }

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
            currentMicURL = audioDir.appendingPathComponent("mic_\(String(format: "%03d", currentChunkIndex)).wav")

            guard let micURL = currentMicURL else { return }

            let inputFormat = engine.inputNode.outputFormat(forBus: 0)

            // Use same format as input (WAV/PCM) to avoid conversion issues
            audioFile = try AVAudioFile(
                forWriting: micURL,
                settings: inputFormat.settings,
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

    private func createAssetWriter(url: URL, sampleRate: Int = 44100) throws -> AVAssetWriter {
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

        print("AudioCaptureService: Created AVAssetWriter at \(url.lastPathComponent) with sample rate \(sampleRate)")

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

/// MARK: - SCStreamDelegate

extension AudioCaptureService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("AudioCaptureService: System audio stream stopped with error: \(error)")
    }
}

// MARK: - SCStreamOutput

extension AudioCaptureService: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Skip video frames - we only want audio
        guard type == .audio else { return }

        // Log first few frames for debugging
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

        // Create a copy of the sample buffer that will persist beyond this callback
        // This is necessary because the original buffer is only valid during the callback
        var copiedBuffer: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopy(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleBufferOut: &copiedBuffer)

        guard copyStatus == noErr, let bufferCopy = copiedBuffer else {
            print("AudioCaptureService: Failed to copy sample buffer, status: \(copyStatus)")
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Track frame count
            self.systemAudioFrameCount += 1

            // Log periodically
            if self.systemAudioFrameCount <= 5 || self.systemAudioFrameCount % 100 == 0 {
                print("AudioCaptureService: System audio frame \(self.systemAudioFrameCount) received, \(numSamples) samples")
            }

            // Calculate audio level from the sample buffer
            if let blockBuffer = CMSampleBufferGetDataBuffer(bufferCopy) {
                var length: Int = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

                if let data = dataPointer, length > 0 {
                    let floatCount = length / MemoryLayout<Float>.size
                    if floatCount > 0 {
                        let floatPointer = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: floatCount)
                        var sum: Float = 0
                        for i in 0..<min(floatCount, 1024) {
                            sum += abs(floatPointer[i])
                        }
                        let average = sum / Float(min(floatCount, 1024))
                        self.systemLevel = average * 10
                    }
                }
            }

            // Write to system audio file
            guard let writer = self.systemWriter,
                  let input = self.systemWriterInput else {
                if self.systemAudioFrameCount <= 5 {
                    print("AudioCaptureService: System audio - no writer available")
                }
                return
            }

            guard writer.status == .writing else {
                if self.systemAudioFrameCount <= 5 {
                    print("AudioCaptureService: System audio - writer status is \(writer.status.rawValue), not writing")
                }
                return
            }

            guard input.isReadyForMoreMediaData else {
                if self.systemAudioFrameCount <= 5 {
                    print("AudioCaptureService: System audio - input not ready for more data")
                }
                return
            }

            let success = input.append(bufferCopy)
            if !success && self.systemAudioFrameCount <= 5 {
                print("AudioCaptureService: System audio - failed to append sample buffer")
            }
        }
    }
}

/// MARK: - AVAudioPCMBuffer Extension

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
