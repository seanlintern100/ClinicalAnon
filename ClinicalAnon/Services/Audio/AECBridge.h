//
//  AECBridge.h
//  ClinicalAnon
//
//  Purpose: Objective-C++ bridge for software echo cancellation
//  This wraps the echo cancellation implementation for use from Swift
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Software echo cancellation bridge
/// Uses signal processing to remove echo from microphone input
/// by subtracting the reference signal (system audio / far-end)
@interface AECBridge : NSObject

/// Initialize with sample rate
/// - Parameter sampleRate: Audio sample rate in Hz (e.g., 48000)
- (instancetype)initWithSampleRate:(int)sampleRate;

/// Initialize with sample rate and noise suppression setting
/// - Parameters:
///   - sampleRate: Audio sample rate in Hz (e.g., 48000)
///   - noiseSuppressionEnabled: Whether to enable WebRTC noise suppression
- (instancetype)initWithSampleRate:(int)sampleRate noiseSuppressionEnabled:(BOOL)noiseSuppressionEnabled;

/// Process reference signal (system audio / far-end)
/// Call this with system audio samples to establish the echo reference
/// - Parameters:
///   - samples: Pointer to float audio samples
///   - count: Number of samples
- (void)processReferenceFrame:(const float *)samples count:(int)count;

/// Process and clean microphone signal (near-end)
/// Echo cancellation is applied in-place
/// - Parameters:
///   - samples: Pointer to float audio samples (modified in-place)
///   - count: Number of samples
- (void)processCaptureFrame:(float *)samples count:(int)count;

/// Set estimated delay between speaker output and mic pickup
/// - Parameter delayMs: Delay in milliseconds (typical range: 20-100ms)
- (void)setStreamDelayMs:(int)delayMs;

/// Whether echo cancellation is currently active
@property (nonatomic, readonly) BOOL isActive;

/// Whether the last processed capture frame contained voice
/// Updated after each call to processCaptureFrame
@property (nonatomic, readonly) BOOL hasVoice;

/// Get the voice probability (0.0-1.0) from the last processed frame
/// Only valid if VAD is enabled
@property (nonatomic, readonly) float voiceProbability;

/// Reset the AEC state (call when starting a new session)
- (void)reset;

@end

NS_ASSUME_NONNULL_END
