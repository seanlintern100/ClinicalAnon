//
//  VoiceProcessingAudioCapture.swift
//  ClinicalAnon
//
//  Purpose: Microphone capture with echo cancellation using VoiceProcessingIO AudioUnit
//  Organization: 3 Big Things
//
//  This uses Apple's VoiceProcessingIO AudioUnit directly instead of AVAudioEngine's
//  voice processing mode, which can create aggregate devices on macOS.
//

import Foundation
import AVFoundation
import AudioToolbox
import CoreAudio

/// Callback context for audio rendering
private class VPIOCallbackContext {
    weak var capture: VoiceProcessingAudioCapture?
    init(capture: VoiceProcessingAudioCapture) {
        self.capture = capture
    }
}

/// Microphone capture with hardware echo cancellation via VoiceProcessingIO
class VoiceProcessingAudioCapture {

    // MARK: - Configuration

    private let sampleRate: Double
    private let inputDeviceID: AudioDeviceID?

    // MARK: - Audio Unit

    fileprivate var audioUnit: AudioUnit?
    private var callbackContext: VPIOCallbackContext?

    // MARK: - Output

    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?

    // MARK: - State

    private(set) var isRunning: Bool = false
    private(set) var echoSuppressionEnabled: Bool = false

    // MARK: - Callbacks

    var audioLevelCallback: ((Float) -> Void)?
    var errorCallback: ((Error) -> Void)?

    // MARK: - Initialization

    /// Initialize with sample rate and optional input device
    /// - Parameters:
    ///   - sampleRate: Sample rate for capture (default 48000 for compatibility)
    ///   - inputDeviceID: Specific input device, or nil for system default
    init(sampleRate: Double = 48000, inputDeviceID: AudioDeviceID? = nil) {
        self.sampleRate = sampleRate
        self.inputDeviceID = inputDeviceID
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// Start capturing audio to the specified file URL
    /// - Parameter fileURL: URL to write audio file (WAV format)
    func start(writingTo fileURL: URL) throws {
        guard !isRunning else {
            print("VoiceProcessingAudioCapture: Already running")
            return
        }

        audioFileURL = fileURL

        // Create audio unit
        try setupAudioUnit()

        // Create output file
        try setupAudioFile(url: fileURL)

        // Start the audio unit
        let status = AudioUnitInitialize(audioUnit!)
        guard status == noErr else {
            throw VPIOError.initializationFailed(status)
        }

        let startStatus = AudioOutputUnitStart(audioUnit!)
        guard startStatus == noErr else {
            throw VPIOError.startFailed(startStatus)
        }

        isRunning = true
        print("VoiceProcessingAudioCapture: Started with echo cancellation: \(echoSuppressionEnabled)")
    }

    /// Stop capturing audio
    func stop() {
        guard isRunning, let unit = audioUnit else { return }

        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)

        audioUnit = nil
        audioFile = nil
        isRunning = false
        callbackContext = nil

        print("VoiceProcessingAudioCapture: Stopped")
    }

    // MARK: - Audio Unit Setup

    private func setupAudioUnit() throws {
        // Describe VoiceProcessingIO audio unit
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_VoiceProcessingIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw VPIOError.componentNotFound
        }

        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let audioUnit = unit else {
            throw VPIOError.instanceCreationFailed(status)
        }

        self.audioUnit = audioUnit

        // Enable input (bus 1)
        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,  // Input bus
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            throw VPIOError.propertySetFailed("EnableIO Input", status)
        }

        // Disable output (bus 0) - we're only capturing, not playing
        // Note: We still need the output bus configured for echo reference
        var enableOutput: UInt32 = 1
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,  // Output bus
            &enableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        // Output enable can fail on some systems, continue anyway
        if status != noErr {
            print("VoiceProcessingAudioCapture: Output enable status: \(status) (may be OK)")
        }

        // Set input device if specified
        if let deviceID = inputDeviceID {
            var device = deviceID
            status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &device,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status == noErr {
                print("VoiceProcessingAudioCapture: Set input device ID: \(deviceID)")
            } else {
                print("VoiceProcessingAudioCapture: Failed to set input device: \(status)")
            }
        }

        // Configure audio format
        var streamFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        // Set format on input bus (what we receive from mic)
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,  // Output scope of input bus = what we read
            1,  // Input bus
            &streamFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            throw VPIOError.propertySetFailed("StreamFormat Input", status)
        }

        // Set format on output bus (for echo reference)
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,  // Input scope of output bus = what we write
            0,  // Output bus
            &streamFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        if status != noErr {
            print("VoiceProcessingAudioCapture: Output format status: \(status) (may be OK)")
        }

        // Enable voice processing (echo cancellation)
        var bypassVP: UInt32 = 0  // 0 = voice processing enabled
        status = AudioUnitSetProperty(
            audioUnit,
            kAUVoiceIOProperty_BypassVoiceProcessing,
            kAudioUnitScope_Global,
            0,
            &bypassVP,
            UInt32(MemoryLayout<UInt32>.size)
        )
        if status == noErr {
            echoSuppressionEnabled = true
            print("VoiceProcessingAudioCapture: Echo cancellation enabled")
        } else {
            print("VoiceProcessingAudioCapture: Echo cancellation not available: \(status)")
        }

        // CRITICAL: Disable automatic ducking of other audio
        // Without this, system audio (remote participant) gets quieter during recording
        var duckingDisabled: UInt32 = 0  // 0 = ducking disabled
        let duckingStatus = AudioUnitSetProperty(
            audioUnit,
            AudioUnitPropertyID(2013),  // kAUVoiceIOProperty_DuckNonVoiceAudio
            kAudioUnitScope_Global,
            0,
            &duckingDisabled,
            UInt32(MemoryLayout<UInt32>.size)
        )
        if duckingStatus == noErr {
            print("VoiceProcessingAudioCapture: Audio ducking DISABLED - system audio will play at normal volume")
        } else {
            print("VoiceProcessingAudioCapture: Could not disable ducking: \(duckingStatus)")
        }

        // Disable AGC (automatic gain control) - we want natural audio levels
        var agcDisabled: UInt32 = 0
        AudioUnitSetProperty(
            audioUnit,
            kAUVoiceIOProperty_VoiceProcessingEnableAGC,
            kAudioUnitScope_Global,
            0,
            &agcDisabled,
            UInt32(MemoryLayout<UInt32>.size)
        )

        // Set up render callback for OUTPUT bus (provides silence for echo reference)
        // VoiceProcessingIO REQUIRES valid output audio to function - without this,
        // the downlink DSP fails with "audio time stamp does not have valid sample time"
        var renderCallback = AURenderCallbackStruct(
            inputProc: silenceRenderCallback,
            inputProcRefCon: nil
        )

        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,  // Input scope of output bus
            0,  // Output bus
            &renderCallback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        if status == noErr {
            print("VoiceProcessingAudioCapture: Output render callback set (silence provider)")
        } else {
            print("VoiceProcessingAudioCapture: Could not set output render callback: \(status)")
        }

        // Set up input callback for CAPTURE
        callbackContext = VPIOCallbackContext(capture: self)
        var callbackStruct = AURenderCallbackStruct(
            inputProc: inputCallback,
            inputProcRefCon: Unmanaged.passUnretained(callbackContext!).toOpaque()
        )

        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            throw VPIOError.propertySetFailed("InputCallback", status)
        }

        print("VoiceProcessingAudioCapture: Audio unit configured at \(sampleRate) Hz")
    }

    private func setupAudioFile(url: URL) throws {
        // Remove existing file
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Create AVAudioFormat matching our stream format
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw VPIOError.formatCreationFailed
        }

        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        print("VoiceProcessingAudioCapture: Created audio file at \(url.path)")
    }

    // MARK: - Audio Processing

    fileprivate func processInputBuffer(_ buffer: UnsafeMutablePointer<AudioBufferList>, frameCount: UInt32) {
        guard let file = audioFile else { return }

        // Get the audio data
        let audioBuffer = buffer.pointee.mBuffers
        guard let data = audioBuffer.mData else { return }

        let floatData = data.assumingMemoryBound(to: Float.self)

        // Calculate level for UI
        var sum: Float = 0
        for i in 0..<Int(frameCount) {
            sum += abs(floatData[i])
        }
        let level = sum / Float(max(frameCount, 1))
        audioLevelCallback?(level)

        // Create PCM buffer and write to file
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        // Copy data to buffer
        if let channelData = pcmBuffer.floatChannelData?[0] {
            memcpy(channelData, floatData, Int(frameCount) * MemoryLayout<Float>.size)
        }

        // Write to file
        do {
            try file.write(from: pcmBuffer)
        } catch {
            print("VoiceProcessingAudioCapture: Write error: \(error)")
        }
    }
}

// MARK: - Silence Render Callback (for output bus)

/// Provides silence to the output bus so VoiceProcessingIO has valid audio timestamps
private func silenceRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    // Fill output buffers with silence
    guard let bufferList = ioData else { return noErr }

    let numBuffers = Int(bufferList.pointee.mNumberBuffers)
    for i in 0..<numBuffers {
        let buffer = UnsafeMutableAudioBufferListPointer(bufferList)[i]
        if let data = buffer.mData {
            memset(data, 0, Int(buffer.mDataByteSize))
        }
    }

    return noErr
}

// MARK: - Input Callback

private func inputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {

    let context = Unmanaged<VPIOCallbackContext>.fromOpaque(inRefCon).takeUnretainedValue()
    guard let capture = context.capture, let audioUnit = capture.audioUnit else {
        return noErr
    }

    // Allocate buffer for audio data
    var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: inNumberFrames * 4,
            mData: malloc(Int(inNumberFrames * 4))
        )
    )

    defer {
        free(bufferList.mBuffers.mData)
    }

    // Render audio from the input
    let status = AudioUnitRender(
        audioUnit,
        ioActionFlags,
        inTimeStamp,
        1,  // Input bus
        inNumberFrames,
        &bufferList
    )

    guard status == noErr else {
        return status
    }

    // Process the audio
    capture.processInputBuffer(&bufferList, frameCount: inNumberFrames)

    return noErr
}

// MARK: - Errors

enum VPIOError: Error, LocalizedError {
    case componentNotFound
    case instanceCreationFailed(OSStatus)
    case initializationFailed(OSStatus)
    case startFailed(OSStatus)
    case propertySetFailed(String, OSStatus)
    case formatCreationFailed

    var errorDescription: String? {
        switch self {
        case .componentNotFound:
            return "VoiceProcessingIO audio unit not found"
        case .instanceCreationFailed(let status):
            return "Failed to create audio unit instance: \(status)"
        case .initializationFailed(let status):
            return "Failed to initialize audio unit: \(status)"
        case .startFailed(let status):
            return "Failed to start audio unit: \(status)"
        case .propertySetFailed(let prop, let status):
            return "Failed to set \(prop): \(status)"
        case .formatCreationFailed:
            return "Failed to create audio format"
        }
    }
}
