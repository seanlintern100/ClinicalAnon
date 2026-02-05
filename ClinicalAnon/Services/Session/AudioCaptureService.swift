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

    /// Duration of each audio chunk in seconds (1 minute for faster transcription)
    private let chunkDuration: TimeInterval = 60

    /// Overlap between chunks for better transcription continuity (30 seconds)
    private let overlapDuration: TimeInterval = 30

    /// Sample rate for microphone audio (WhisperKit expects 16kHz)
    private let sampleRate: Double = 16000

    /// Sample rate for system audio (match AEC at 48kHz for echo cancellation)
    private let systemSampleRate: Int = 48000

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
    @Published private(set) var hasVoiceActivity: Bool = false
    @Published private(set) var voiceProbability: Float = 0

    /// Indicates whether system audio capture is healthy (receiving frames)
    @Published private(set) var systemAudioHealthy: Bool = true

    /// Number of consecutive system audio restart attempts
    private var systemAudioRestartAttempts: Int = 0
    private let maxRestartAttempts: Int = 3

    /// Track when system audio last worked to reset restart counter
    private var lastSuccessfulSystemAudioTime: Date?
    private let restartCounterResetInterval: TimeInterval = 30  // Reset counter after 30s of good audio

    // MARK: - Audio Device Selection

    @Published var availableInputDevices: [AudioDevice] = []
    @Published var selectedInputDevice: AudioDevice?

    // MARK: - Audio Capture

    private var microphoneEngine: AVAudioEngine?
    private var systemAudioStream: SCStream?
    private var streamConfiguration: SCStreamConfiguration?

    // MARK: - Software Echo Cancellation

    private var aecProcessor: AECProcessor?

    /// Direct bridge reference for background thread access (thread-safe Obj-C++)
    private nonisolated(unsafe) var aecBridge: AECBridge?

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

    // MARK: - Process Activity (prevent App Nap during recording)

    /// Activity token to prevent macOS from throttling or suspending the app during recording
    private var processActivity: NSObjectProtocol?

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

        // Begin activity to prevent App Nap from throttling audio capture
        processActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .latencyCritical],
            reason: "Recording live session audio"
        )
        print("AudioCaptureService: Started process activity to prevent App Nap")

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
            // IMPORTANT: Initialize system audio writer BEFORE starting the stream
            // Otherwise audio frames arrive before writer is ready and are dropped
            try startNewChunk()

            try await setupSystemAudioCapture()
            print("AudioCaptureService: System audio capture started")
            systemAudioHealthy = true
            systemAudioRestartAttempts = 0  // Reset restart counter on success
        } catch {
            print("AudioCaptureService: System audio capture failed (optional): \(error)")
            systemAudioHealthy = false
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

        // Pause AVAudioEngine if active
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

        // Stop AVAudioEngine if active
        if let engine = microphoneEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            print("AudioCaptureService: Stopped AVAudioEngine")
        }
        microphoneEngine = nil

        // Reset AEC processor
        aecProcessor?.reset()
        aecProcessor = nil
        aecBridge = nil

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

        // End process activity
        if let activity = processActivity {
            ProcessInfo.processInfo.endActivity(activity)
            processActivity = nil
            print("AudioCaptureService: Ended process activity")
        }

        currentSession = nil
        sessionStartTime = nil
        isCapturing = false
        systemAudioHealthy = true  // Reset for next session
        systemAudioRestartAttempts = 0
        lastSuccessfulSystemAudioTime = nil
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

    // MARK: - Microphone Setup with Software Echo Cancellation

    private func setupMicrophoneCapture() throws {
        print("AudioCaptureService: Setting up microphone capture...")

        guard let session = currentSession else {
            throw AudioCaptureError.engineSetupFailed
        }

        // Create the audio file URL for this chunk
        let sessionDir = SessionStorageService.sessionDirectory(for: session)
        let audioDir = sessionDir.appendingPathComponent("audio", isDirectory: true)

        // Ensure audio directory exists
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        // Use WAV format
        currentMicURL = audioDir.appendingPathComponent("mic_\(String(format: "%03d", currentChunkIndex)).wav")

        guard let micURL = currentMicURL else {
            throw AudioCaptureError.engineSetupFailed
        }

        // Check if echo cancellation is enabled in settings (defaults to ON)
        let echoEnabled = UserDefaults.standard.object(forKey: SettingsKeys.voiceProcessingEnabled) as? Bool ?? true

        if echoEnabled {
            // Initialize software AEC processor
            // Use 48kHz for best quality - will resample system audio to match
            aecProcessor = AECProcessor(sampleRate: 48000)

            // Store bridge reference for background thread access
            aecBridge = aecProcessor?.underlyingBridge

            // Get stream delay from settings (default 50ms)
            let streamDelayMs = UserDefaults.standard.integer(forKey: SettingsKeys.aecStreamDelayMs)
            if streamDelayMs > 0 {
                aecProcessor?.setStreamDelay(ms: streamDelayMs)
            }

            print("AudioCaptureService: Software AEC initialized - echo cancellation enabled")
        } else {
            print("AudioCaptureService: Echo cancellation disabled by user setting")
            aecProcessor = nil
            aecBridge = nil
        }

        // Use standard AVAudioEngine for mic capture
        // Software AEC will process the audio before writing to file
        try setupAVAudioEngineCapture(url: micURL)
    }

    /// Set up microphone capture using AVAudioEngine (software AEC applied in handleMicrophoneBuffer)
    private func setupAVAudioEngineCapture(url: URL) throws {
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Create audio engine
        let engine = AVAudioEngine()
        microphoneEngine = engine

        let inputNode = engine.inputNode

        // Assign specific input device if selected
        if let device = selectedInputDevice {
            print("AudioCaptureService: Using selected input device: \(device.name) (ID: \(device.id))")
            assignAudioInput(inputNode: inputNode, deviceID: device.id)
        } else {
            print("AudioCaptureService: Using system default input device")
        }

        // Get input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("AudioCaptureService: Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")

        guard inputFormat.sampleRate > 0 else {
            print("AudioCaptureService: Invalid input format")
            throw AudioCaptureError.engineSetupFailed
        }

        // When AEC is enabled, we mix stereo to mono before processing
        // So the output file should be mono format
        let fileFormat: AVAudioFormat
        if aecProcessor != nil && inputFormat.channelCount > 1 {
            // Create mono format at same sample rate
            guard let mono = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 1) else {
                throw AudioCaptureError.engineSetupFailed
            }
            fileFormat = mono
            print("AudioCaptureService: Output format: \(mono.sampleRate) Hz, 1 channel (mono for AEC)")
        } else {
            fileFormat = inputFormat
            print("AudioCaptureService: Output format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")
        }

        // Create audio file with appropriate format
        audioFile = try AVAudioFile(forWriting: url, settings: fileFormat.settings)
        print("AudioCaptureService: Created audio file at: \(url.path)")

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            self?.handleMicrophoneBuffer(buffer)
        }

        // Start the engine
        engine.prepare()
        try engine.start()

        if self.aecProcessor != nil {
            print("AudioCaptureService: AVAudioEngine started with software echo cancellation (stereo→mono)")
        } else {
            print("AudioCaptureService: AVAudioEngine started (no echo cancellation)")
        }
    }

    private var currentMicURL: URL?
    private var audioFile: AVAudioFile?

    private var micBufferCount: Int = 0

    /// Mono buffer for AEC processing (reused to avoid allocations)
    private var monoBuffer: AVAudioPCMBuffer?
    private var monoFormat: AVAudioFormat?

    private func handleMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        // If stereo, mix to mono first (AEC requires mono input)
        // This is CRITICAL: AEC must process ALL audio, not just one channel
        let monoSamples: UnsafeMutablePointer<Float>
        let outputBuffer: AVAudioPCMBuffer

        if channelCount >= 2 {
            // Create or reuse mono buffer
            if monoBuffer == nil || monoBuffer!.frameCapacity < AVAudioFrameCount(frameCount) {
                monoFormat = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: 1)
                if let format = monoFormat {
                    monoBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount * 2))
                    print("AudioCaptureService: Created mono buffer for stereo→mono conversion (AEC requires mono)")
                }
            }

            if let mono = monoBuffer, let monoData = mono.floatChannelData?[0] {
                // Mix stereo to mono: (L + R) / 2
                let left = channelData[0]
                let right = channelData[1]
                for i in 0..<frameCount {
                    monoData[i] = (left[i] + right[i]) * 0.5
                }
                mono.frameLength = AVAudioFrameCount(frameCount)

                monoSamples = monoData
                outputBuffer = mono
            } else {
                // Fallback: just process channel 0 of original buffer
                monoSamples = channelData[0]
                outputBuffer = buffer
            }
        } else {
            // Already mono
            monoSamples = channelData[0]
            outputBuffer = buffer
        }

        // Apply software echo cancellation if enabled
        if let aec = aecProcessor {
            aec.process(samples: monoSamples, count: frameCount)
        }

        // Throttle UI level updates (every 10 buffers ~= 85ms at 4096 samples/48kHz)
        micBufferCount += 1
        if micBufferCount % 10 == 0 {
            // Calculate audio level for UI meter (sample only first 256 samples for speed)
            var sum: Float = 0
            let sampleCount = min(frameCount, 256)
            for i in 0..<sampleCount {
                sum += abs(monoSamples[i])
            }
            let average = sum / Float(max(sampleCount, 1))

            // Get voice activity from AEC processor (VAD is built into audio processing)
            let hasVoice = aecProcessor?.hasVoice ?? false
            let voiceProb = aecProcessor?.voiceProbability ?? 0

            Task { @MainActor [weak self, average, hasVoice, voiceProb] in
                self?.microphoneLevel = average
                self?.hasVoiceActivity = hasVoice
                self?.voiceProbability = voiceProb
            }
        }

        // Write processed mono buffer to file
        do {
            try audioFile?.write(from: outputBuffer)
        } catch {
            // Only log errors occasionally to avoid spam
            if micBufferCount % 100 == 1 {
                print("AudioCaptureService: Write error: \(error)")
            }
        }
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
        config.sampleRate = 48000  // Match AEC and mic sample rate for echo cancellation
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

        // Add video output handler to suppress "stream output NOT found" errors
        // We don't actually use the video frames, but ScreenCaptureKit requires a handler
        try stream.addStreamOutput(
            self,
            type: .screen,
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

        // Check if system audio stream died silently (no frames received this chunk)
        let frameCountThisChunk = systemAudioFrameCount
        if frameCountThisChunk == 0 && systemAudioHealthy {
            print("AudioCaptureService: ⚠️ System audio stream appears dead (0 frames in chunk \(chunkIndex)) - triggering restart")
            systemAudioHealthy = false
            Task { @MainActor in
                await self.attemptSystemAudioRestart()
            }
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
            object: AudioChunkReadyInfo(
                sessionId: session.id,
                chunkIndex: chunkIndex,
                chunkStartTime: sessionOffset,
                hasMultipleParticipants: session.hasMultipleParticipants
            )
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
        guard isCapturing else { return }
        guard microphoneEngine != nil else { return }

        print("AudioCaptureService: Rotating to chunk \(currentChunkIndex + 1)")

        // Remove tap from current audio file
        if let engine = microphoneEngine {
            engine.inputNode.removeTap(onBus: 0)
        }
        audioFile = nil

        // Finish current chunk (records references)
        finishCurrentChunk()

        // Reset chunk start time for new chunk
        chunkStartTime = Date()

        // Start new chunk
        do {
            try startNewChunk()

            // Create new mic file URL
            guard let session = currentSession else { return }
            let sessionDir = SessionStorageService.sessionDirectory(for: session)
            let audioDir = sessionDir.appendingPathComponent("audio", isDirectory: true)
            currentMicURL = audioDir.appendingPathComponent("mic_\(String(format: "%03d", currentChunkIndex)).wav")

            guard let micURL = currentMicURL else { return }

            // Set up new audio file and tap
            if let engine = microphoneEngine {
                let inputFormat = engine.inputNode.outputFormat(forBus: 0)

                // When AEC is enabled, use mono format (we mix stereo to mono before AEC)
                let fileFormat: AVAudioFormat
                if aecProcessor != nil && inputFormat.channelCount > 1 {
                    fileFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 1)!
                } else {
                    fileFormat = inputFormat
                }

                audioFile = try AVAudioFile(
                    forWriting: micURL,
                    settings: fileFormat.settings,
                    commonFormat: fileFormat.commonFormat,
                    interleaved: fileFormat.isInterleaved
                )

                engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
                    self?.handleMicrophoneBuffer(buffer)
                }

                print("AudioCaptureService: Started new chunk \(currentChunkIndex)")
            }
        } catch {
            print("AudioCaptureService: Failed to start new chunk: \(error)")
        }
    }

    // MARK: - Asset Writer Creation

    private func createAssetWriter(url: URL, sampleRate: Int = 48000) throws -> AVAssetWriter {
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

}

// MARK: - SCStreamDelegate

extension AudioCaptureService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let nsError = error as NSError
        // Log detailed error info to help diagnose -3821 "Stream was stopped by the system"
        print("AudioCaptureService: System audio stream stopped with error: \(error) (code: \(nsError.code))")
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            print("AudioCaptureService: Underlying error: \(underlyingError)")
        }
        print("AudioCaptureService: Error domain: \(nsError.domain), userInfo: \(nsError.userInfo)")

        // Dispatch to main actor for state updates and restart attempt
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Mark system audio as unhealthy and reset success tracking
            self.systemAudioHealthy = false
            self.lastSuccessfulSystemAudioTime = nil

            // Error -3821 = "Stream was stopped by the system"
            // This can happen due to audio driver conflicts, display changes, etc.
            if nsError.code == -3821 && self.isCapturing {
                await self.attemptSystemAudioRestart()
            }
        }
    }

    /// Attempt to restart system audio capture after an error
    @MainActor
    private func attemptSystemAudioRestart() async {
        // Use exponential backoff: 1s, 2s, 4s, then cap at 5s
        let backoffSeconds = min(pow(2.0, Double(systemAudioRestartAttempts)), 5.0)

        if systemAudioRestartAttempts >= maxRestartAttempts {
            // Don't give up permanently - schedule a delayed retry
            print("AudioCaptureService: ⚠️ System audio restart failed \(maxRestartAttempts) times consecutively - will retry in 10s")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                guard self.isCapturing && !self.systemAudioHealthy else { return }
                // Reset counter to allow more attempts
                self.systemAudioRestartAttempts = 0
                await self.attemptSystemAudioRestart()
            }
            return
        }

        systemAudioRestartAttempts += 1
        print("AudioCaptureService: Attempting system audio restart (attempt \(systemAudioRestartAttempts)/\(maxRestartAttempts), backoff: \(Int(backoffSeconds))s)...")

        // Clean up old stream
        systemAudioStream = nil
        systemWriter = nil
        systemWriterInput = nil
        lastSuccessfulSystemAudioTime = nil  // Reset success tracking

        // Wait with exponential backoff before restarting
        let sleepNanos = UInt64(backoffSeconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: sleepNanos)

        guard isCapturing else {
            print("AudioCaptureService: Capture stopped during restart wait - aborting restart")
            return
        }

        do {
            // Initialize new system audio writer
            try startNewChunk()

            // Restart system audio capture
            try await setupSystemAudioCapture()

            systemAudioHealthy = true
            print("AudioCaptureService: ✓ System audio restart successful (attempt \(systemAudioRestartAttempts))")
        } catch {
            print("AudioCaptureService: System audio restart failed: \(error)")
            systemAudioHealthy = false
            // Trigger another attempt (will use backoff)
            if systemAudioRestartAttempts < maxRestartAttempts {
                await attemptSystemAudioRestart()
            }
        }
    }
}

// MARK: - SCStreamOutput

extension AudioCaptureService: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Silently ignore video frames (we added video output to suppress errors)
        guard type == .audio else { return }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

        // Extract float samples for AEC reference (do on this thread to avoid copies)
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == noErr, let data = dataPointer, length > 0 else { return }

        let floatCount = length / MemoryLayout<Float>.size
        guard floatCount > 0 else { return }

        let floatPointer = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: floatCount)

        // Feed AEC reference directly on this background thread
        // Using try_lock to avoid blocking if capture is processing
        aecBridge?.processReferenceFrame(floatPointer, count: Int32(floatCount))

        // Copy sample buffer for writing (must happen before callback returns)
        var copiedBuffer: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopy(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleBufferOut: &copiedBuffer)

        guard copyStatus == noErr, let bufferCopy = copiedBuffer else { return }

        // Calculate level for UI (quick computation on this thread)
        var sum: Float = 0
        let sampleCount = min(floatCount, 256)
        for i in 0..<sampleCount {
            sum += abs(floatPointer[i])
        }
        let avgLevel = sum / Float(max(sampleCount, 1)) * 10

        // Dispatch UI updates and file writing to main thread
        Task { @MainActor [weak self, bufferCopy, avgLevel, numSamples] in
            guard let self = self else { return }

            self.systemAudioFrameCount += 1

            // Update UI level (throttled)
            if self.systemAudioFrameCount % 5 == 0 {
                self.systemLevel = avgLevel
            }

            // Track successful audio reception - reset restart counter after stable period
            let now = Date()
            if self.lastSuccessfulSystemAudioTime == nil {
                self.lastSuccessfulSystemAudioTime = now
            }
            if let lastSuccess = self.lastSuccessfulSystemAudioTime,
               now.timeIntervalSince(lastSuccess) >= self.restartCounterResetInterval,
               self.systemAudioRestartAttempts > 0 {
                print("AudioCaptureService: System audio stable for \(Int(self.restartCounterResetInterval))s - resetting restart counter")
                self.systemAudioRestartAttempts = 0
            }
            self.lastSuccessfulSystemAudioTime = now


            // Write to file
            guard let writer = self.systemWriter,
                  let input = self.systemWriterInput,
                  writer.status == .writing,
                  input.isReadyForMoreMediaData else {
                // Debug: Log when frames are dropped
                if self.systemAudioFrameCount <= 5 {
                    print("AudioCaptureService: [DEBUG] System audio frame \(self.systemAudioFrameCount) dropped - writer not ready (writer: \(self.systemWriter != nil), status: \(self.systemWriter?.status.rawValue ?? -1))")
                }
                return
            }

            input.append(bufferCopy)
        }
    }
}

// MARK: - Notifications

/// Info passed with audio chunk ready notification
struct AudioChunkReadyInfo {
    let sessionId: UUID
    let chunkIndex: Int
    /// Start time of this chunk relative to session start (in seconds)
    let chunkStartTime: TimeInterval
    /// Whether speaker diarization should be applied (multiple remote participants)
    let hasMultipleParticipants: Bool
}

extension Notification.Name {
    static let audioChunkReady = Notification.Name("audioChunkReady")
}
