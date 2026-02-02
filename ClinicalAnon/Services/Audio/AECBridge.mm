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
#include <pthread.h>
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
        _lock = OS_UNFAIR_LOCK_INIT;  // Initialize spinlock
        _hasReceivedReference = NO;  // Wait for reference before processing capture
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
            NSLog(@"AECBridge: WebRTC AEC3 initialized at %d Hz, frame size %d samples",
                  sampleRate, _expectedFrameSize);
        } else {
            _isActive = NO;
            NSLog(@"AECBridge: Failed to create WebRTC AudioProcessing");
        }
    }
    return self;
}

- (void)dealloc {
    _apm = nullptr;
    NSLog(@"AECBridge: Deallocated");
}

- (BOOL)isActive {
    return _isActive && _apm != nullptr;
}

- (void)processReferenceFrame:(const float *)samples count:(int)count {
    if (!_apm || !samples || count <= 0) return;

    // Only process if we have at least one full 10ms frame
    if (count < _expectedFrameSize) return;

    static int refCallCount = 0;
    refCallCount++;
    if (refCallCount <= 5 || refCallCount % 100 == 0) {
        NSLog(@"AECBridge: processReferenceFrame called, count=%d, call#%d, hasRef=%d",
              count, refCallCount, _hasReceivedReference);
    }

    // Configure stream for mono audio at our sample rate
    webrtc::StreamConfig streamConfig(_sampleRate, 1);  // 1 channel (mono)

    // Process ALL complete 10ms frames to ensure AEC has full reference data
    int framesToProcess = count / _expectedFrameSize;

    if (refCallCount <= 5) {
        NSLog(@"AECBridge: Processing %d reference frames (of %d samples)", framesToProcess, count);
    }

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
            NSLog(@"AECBridge: Reference audio established - enabling AEC on capture");
        }
    }

    if (refCallCount <= 5) {
        NSLog(@"AECBridge: processReferenceFrame done");
    }
}

- (void)processCaptureFrame:(float *)samples count:(int)count {
    if (!_apm || !samples || count <= 0) return;

    // Only process if we have at least one full 10ms frame
    if (count < _expectedFrameSize) return;

    // Skip AEC processing until we've received reference audio
    // This prevents calling ProcessStream before ProcessReverseStream
    if (!_hasReceivedReference) {
        static int skipCount = 0;
        skipCount++;
        if (skipCount <= 3 || skipCount % 100 == 0) {
            NSLog(@"AECBridge: Skipping capture frame (waiting for reference), skip#%d", skipCount);
        }
        return;  // Pass audio through unchanged
    }

    static int capCallCount = 0;
    capCallCount++;
    if (capCallCount <= 3 || capCallCount % 100 == 0) {
        NSLog(@"AECBridge: processCaptureFrame called, count=%d, call#%d", count, capCallCount);
    }

    webrtc::StreamConfig streamConfig(_sampleRate, 1);  // mono

    // Process ALL complete 10ms frames to apply AEC to entire buffer
    // This is critical - only processed samples have echo removed!
    int framesToProcess = count / _expectedFrameSize;

    if (capCallCount <= 3) {
        NSLog(@"AECBridge: Processing %d capture frames (of %d samples)", framesToProcess, count);
    }

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

    if (capCallCount <= 3) {
        NSLog(@"AECBridge: processCaptureFrame done");
    }
}

- (void)setStreamDelayMs:(int)delayMs {
    _streamDelayMs = MAX(0, MIN(delayMs, 500));  // Clamp to 0-500ms
    NSLog(@"AECBridge: Stream delay set to %d ms", _streamDelayMs);
}

- (void)reset {
    if (_apm) {
        // Re-initialize APM for fresh state
        _apm->Initialize();
        NSLog(@"AECBridge: Reset - AEC state cleared");
    }
}

@end
