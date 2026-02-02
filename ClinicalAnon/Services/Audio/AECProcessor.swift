//
//  AECProcessor.swift
//  ClinicalAnon
//
//  Purpose: Swift wrapper for WebRTC AEC3 echo cancellation
//  Coordinates feeding reference audio (system audio) and processing microphone audio
//

import Foundation
import AVFoundation

/// WebRTC AEC3 echo cancellation processor
/// Removes echo from microphone input using the reference signal (system audio)
final class AECProcessor {

    // MARK: - Properties

    private let bridge: AECBridge

    /// Expose bridge for direct thread-safe access from background queues
    var underlyingBridge: AECBridge { bridge }

    /// Sample rate for processing
    let sampleRate: Int

    /// Whether the processor has been initialized successfully
    private(set) var isInitialized: Bool = false

    // MARK: - Initialization

    /// Initialize AEC processor
    /// - Parameters:
    ///   - sampleRate: Audio sample rate in Hz (should match both mic and system audio)
    ///   - noiseSuppressionEnabled: Whether to enable WebRTC noise suppression (default: reads from UserDefaults)
    init(sampleRate: Int = 48000, noiseSuppressionEnabled: Bool? = nil) {
        self.sampleRate = sampleRate

        // Read noise suppression setting from UserDefaults if not explicitly provided
        let nsEnabled = noiseSuppressionEnabled ?? UserDefaults.standard.bool(forKey: SettingsKeys.noiseSuppressionEnabled)

        // Register default value if not set
        if UserDefaults.standard.object(forKey: SettingsKeys.noiseSuppressionEnabled) == nil {
            UserDefaults.standard.set(true, forKey: SettingsKeys.noiseSuppressionEnabled)
        }

        self.bridge = AECBridge(sampleRate: Int32(sampleRate), noiseSuppressionEnabled: nsEnabled)

        // Set default stream delay estimate (50ms is typical for laptop speakers/mic)
        bridge.setStreamDelayMs(50)

        isInitialized = bridge.isActive
#if DEBUG
        if isInitialized {
            print("AECProcessor: WebRTC AEC3 initialized at \(sampleRate) Hz, noise suppression: \(nsEnabled ? "ON" : "OFF")")
        } else {
            print("AECProcessor: Failed to initialize WebRTC AEC3")
        }
#endif
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
    }

    /// Reset the AEC state
    /// Call when starting a new recording session
    func reset() {
        bridge.reset()
#if DEBUG
        print("AECProcessor: Reset")
#endif
    }

    /// Whether the AEC is actively processing
    var isActive: Bool {
        return bridge.isActive
    }

    // MARK: - Voice Activity Detection

    /// Whether voice was detected in the last processed frame
    var hasVoice: Bool {
        return bridge.hasVoice
    }

    /// Voice probability from last processed frame (0.0 = silence, 1.0 = speech)
    var voiceProbability: Float {
        return bridge.voiceProbability
    }
}
