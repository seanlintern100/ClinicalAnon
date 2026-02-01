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

/// Reset the AEC state (call when starting a new session)
- (void)reset;

@end

NS_ASSUME_NONNULL_END
