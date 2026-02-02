//
//  AECBridge.mm
//  ClinicalAnon
//
//  Purpose: WebRTC AEC3 echo cancellation bridge for Objective-C/Swift
//  Uses the WebRTC AudioProcessing module for high-quality acoustic echo cancellation
//

#import "AECBridge.h"

// WebRTC headers
#include "webrtc/api/audio/audio_processing.h"
#include "webrtc/api/scoped_refptr.h"
#include <os/lock.h>

// WebRTC requires 10ms frames
static const int kFrameSizeMs = 10;

@implementation AECBridge {
    rtc::scoped_refptr<webrtc::AudioProcessing> _apm;
    int _sampleRate;
    int _streamDelayMs;
    int _expectedFrameSize;  // Samples per 10ms frame
    BOOL _isActive;
    os_unfair_lock _lock;  // Fast spinlock for serializing APM access
    BOOL _hasReceivedReference;  // Track if we've received reference audio
    int _referenceFramesPending;  // Count reference frames to process before capture
}

- (instancetype)initWithSampleRate:(int)sampleRate {
    self = [super init];
    if (self) {
        _sampleRate = sampleRate;
        _streamDelayMs = 50;  // Default 50ms delay estimate
        _expectedFrameSize = sampleRate / (1000 / kFrameSizeMs);  // 480 at 48kHz
        _lock = OS_UNFAIR_LOCK_INIT;
        _hasReceivedReference = NO;
        _referenceFramesPending = 5;  // Process 5 reference frames before enabling capture

        // Create AudioProcessing with AEC3 enabled
        webrtc::AudioProcessing::Config config;
        config.echo_canceller.enabled = true;
        config.echo_canceller.mobile_mode = false;  // Use full AEC3 (not mobile)
        config.echo_canceller.enforce_high_pass_filtering = true;

        // Disable other processing - we only want AEC
        config.gain_controller1.enabled = false;
        config.gain_controller2.enabled = false;
        config.noise_suppression.enabled = false;
        config.high_pass_filter.enabled = false;

        _apm = webrtc::AudioProcessingBuilder()
            .SetConfig(config)
            .Create();

        if (_apm) {
            _isActive = YES;
#ifdef DEBUG
            NSLog(@"AECBridge: WebRTC AEC3 initialized at %d Hz, frame size %d samples",
                  sampleRate, _expectedFrameSize);
#endif
        } else {
            _isActive = NO;
            NSLog(@"AECBridge: Failed to create WebRTC AudioProcessing");
        }
    }
    return self;
}

- (void)dealloc {
    _apm = nullptr;
}

- (BOOL)isActive {
    return _isActive && _apm != nullptr;
}

- (void)processReferenceFrame:(const float *)samples count:(int)count {
    if (!_apm || !samples || count <= 0) return;

    // Only process if we have at least one full 10ms frame
    if (count < _expectedFrameSize) return;

    // Configure stream for mono audio at our sample rate
    webrtc::StreamConfig streamConfig(_sampleRate, 1);  // 1 channel (mono)

    // Process ALL complete 10ms frames to ensure AEC has full reference data
    int framesToProcess = count / _expectedFrameSize;

    // Lock to prevent concurrent access with ProcessStream
    os_unfair_lock_lock(&_lock);

    for (int frame = 0; frame < framesToProcess; frame++) {
        const float* channelPtr = samples + (frame * _expectedFrameSize);
        const float* const* channelPtrs = &channelPtr;

        // Use AnalyzeReverseStream for reference-only analysis (no output needed)
        _apm->AnalyzeReverseStream(channelPtrs, streamConfig);
    }

    os_unfair_lock_unlock(&_lock);

    // After processing enough reference frames, enable capture processing
    if (!_hasReceivedReference) {
        _referenceFramesPending--;
        if (_referenceFramesPending <= 0) {
            _hasReceivedReference = YES;
#ifdef DEBUG
            NSLog(@"AECBridge: Reference audio established - enabling AEC on capture");
#endif
        }
    }
}

- (void)processCaptureFrame:(float *)samples count:(int)count {
    if (!_apm || !samples || count <= 0) return;

    // Only process if we have at least one full 10ms frame
    if (count < _expectedFrameSize) return;

    // Skip AEC processing until we've received reference audio
    if (!_hasReceivedReference) {
        return;  // Pass audio through unchanged
    }

    webrtc::StreamConfig streamConfig(_sampleRate, 1);  // mono

    // Process ALL complete 10ms frames to apply AEC to entire buffer
    int framesToProcess = count / _expectedFrameSize;

    // Lock to prevent concurrent access with AnalyzeReverseStream
    os_unfair_lock_lock(&_lock);

    // Set stream delay before processing
    _apm->set_stream_delay_ms(_streamDelayMs);

    for (int frame = 0; frame < framesToProcess; frame++) {
        float* channelPtr = samples + (frame * _expectedFrameSize);
        float* const* channelPtrs = &channelPtr;

        // ProcessStream modifies samples in-place with echo removed
        _apm->ProcessStream(channelPtrs, streamConfig, streamConfig, channelPtrs);
    }

    os_unfair_lock_unlock(&_lock);
}

- (void)setStreamDelayMs:(int)delayMs {
    _streamDelayMs = MAX(0, MIN(delayMs, 500));  // Clamp to 0-500ms
#ifdef DEBUG
    NSLog(@"AECBridge: Stream delay set to %d ms", _streamDelayMs);
#endif
}

- (void)reset {
    if (_apm) {
        _apm->Initialize();
        _hasReceivedReference = NO;
        _referenceFramesPending = 5;
#ifdef DEBUG
        NSLog(@"AECBridge: Reset - AEC state cleared");
#endif
    }
}

@end
