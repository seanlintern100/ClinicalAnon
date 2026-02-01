//
//  AECProcessor.swift
//  ClinicalAnon
//
//  Purpose: Swift wrapper for software echo cancellation
//  Coordinates feeding reference audio (system audio) and processing microphone audio
//

import Foundation
import AVFoundation

/// Software echo cancellation using adaptive filtering
/// Removes echo from microphone input by subtracting the system audio reference signal
final class AECProcessor {

    // MARK: - Properties

    private let bridge: AECBridge
    private let processingQueue = DispatchQueue(label: "com.redactor.aec", qos: .userInteractive)

    /// Sample rate for processing
    let sampleRate: Int

    /// Whether the processor has been initialized successfully
    private(set) var isInitialized: Bool = false

    /// Statistics for debugging
    private(set) var referenceFramesProcessed: Int = 0
    private(set) var captureFramesProcessed: Int = 0

    // MARK: - Initialization

    /// Initialize AEC processor
    /// - Parameter sampleRate: Audio sample rate in Hz (should match both mic and system audio)
    init(sampleRate: Int = 48000) {
        self.sampleRate = sampleRate
        self.bridge = AECBridge(sampleRate: Int32(sampleRate))

        // Set default stream delay estimate (50ms is typical for laptop speakers/mic)
        bridge.setStreamDelayMs(50)

        isInitialized = true
        print("AECProcessor: Initialized at \(sampleRate) Hz")
    }

    // MARK: - Public Methods

    /// Feed reference signal (system audio) to the AEC
    /// Call this from the system audio capture callback
    /// - Parameters:
    ///   - samples: Pointer to float audio samples
    ///   - count: Number of samples
    func feedReference(samples: UnsafePointer<Float>, count: Int) {
        guard isInitialized, count > 0 else { return }

        bridge.processReferenceFrame(samples, count: Int32(count))
        referenceFramesProcessed += 1
    }

    /// Feed reference signal from an array
    /// - Parameter samples: Array of float audio samples
    func feedReference(samples: [Float]) {
        samples.withUnsafeBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            feedReference(samples: baseAddress, count: samples.count)
        }
    }

    /// Process microphone audio to remove echo
    /// Echo cancellation is applied in-place
    /// Call this from the microphone capture callback BEFORE writing to file
    /// - Parameters:
    ///   - samples: Pointer to float audio samples (modified in-place)
    ///   - count: Number of samples
    func process(samples: UnsafeMutablePointer<Float>, count: Int) {
        guard isInitialized, count > 0 else { return }

        bridge.processCaptureFrame(samples, count: Int32(count))
        captureFramesProcessed += 1
    }

    /// Process microphone audio from a PCM buffer
    /// - Parameter buffer: AVAudioPCMBuffer to process (modified in-place)
    func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        // Process each channel (usually just mono)
        for channel in 0..<channelCount {
            process(samples: channelData[channel], count: frameCount)
        }
    }

    /// Set the estimated stream delay
    /// This is the acoustic delay between speaker output and microphone pickup
    /// - Parameter ms: Delay in milliseconds (typical range: 20-100ms)
    func setStreamDelay(ms: Int) {
        bridge.setStreamDelayMs(Int32(ms))
        print("AECProcessor: Stream delay set to \(ms) ms")
    }

    /// Reset the AEC state
    /// Call when starting a new recording session
    func reset() {
        bridge.reset()
        referenceFramesProcessed = 0
        captureFramesProcessed = 0
        print("AECProcessor: Reset")
    }

    /// Whether the AEC is actively processing
    var isActive: Bool {
        return bridge.isActive
    }

    // MARK: - Utility Methods

    /// Mix stereo audio to mono
    /// System audio may be stereo but AEC expects mono
    /// - Parameters:
    ///   - stereo: Pointer to interleaved stereo float samples
    ///   - frameCount: Number of frames (each frame has 2 samples for stereo)
    /// - Returns: Mono float array
    static func mixToMono(stereo: UnsafePointer<Float>, frameCount: Int) -> [Float] {
        var mono = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            mono[i] = (stereo[i * 2] + stereo[i * 2 + 1]) * 0.5
        }
        return mono
    }

    /// Mix non-interleaved stereo channels to mono
    /// - Parameters:
    ///   - left: Left channel samples
    ///   - right: Right channel samples
    ///   - count: Number of samples per channel
    /// - Returns: Mono float array
    static func mixToMono(left: UnsafePointer<Float>, right: UnsafePointer<Float>, count: Int) -> [Float] {
        var mono = [Float](repeating: 0, count: count)
        for i in 0..<count {
            mono[i] = (left[i] + right[i]) * 0.5
        }
        return mono
    }

    /// Extract float samples from CMSampleBuffer
    /// - Parameter sampleBuffer: The sample buffer to extract from
    /// - Returns: Float array of audio samples, or nil if extraction fails
    static func extractFloatSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == noErr, let data = dataPointer, length > 0 else {
            return nil
        }

        // Assume float32 format
        let floatCount = length / MemoryLayout<Float>.size
        guard floatCount > 0 else { return nil }

        let floatPointer = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: floatCount)
        return Array(UnsafeBufferPointer(start: floatPointer, count: floatCount))
    }
}
