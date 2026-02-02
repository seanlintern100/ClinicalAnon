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
#include "webrtc/api/audio/audio_processing_statistics.h"
#include "webrtc/api/scoped_refptr.h"
#include <pthread.h>
#include <os/lock.h>
#include <math.h>

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

    // Log audio levels to verify format (should be in [-1, 1] range)
    if (refCallCount <= 5 || refCallCount % 500 == 0) {
        float minVal = 0, maxVal = 0, sum = 0;
        for (int i = 0; i < MIN(count, 480); i++) {
            float s = samples[i];
            if (s < minVal) minVal = s;
            if (s > maxVal) maxVal = s;
            sum += fabsf(s);
        }
        float avgLevel = sum / MIN(count, 480);
        NSLog(@"AECBridge: REF #%d - samples=%d, range=[%.4f, %.4f], avgLevel=%.4f",
              refCallCount, count, minVal, maxVal, avgLevel);
    }

    // Configure stream for mono audio at our sample rate
    webrtc::StreamConfig streamConfig(_sampleRate, 1);  // 1 channel (mono)

    // Process ALL complete 10ms frames to ensure AEC has full reference data
    int framesToProcess = count / _expectedFrameSize;

    // Lock to prevent concurrent access with ProcessStream
    os_unfair_lock_lock(&_lock);

    int lastError = 0;
    for (int frame = 0; frame < framesToProcess; frame++) {
        const float* channelPtr = samples + (frame * _expectedFrameSize);
        const float* const* channelPtrs = &channelPtr;

        // Use AnalyzeReverseStream for reference-only analysis (no output needed)
        int err = _apm->AnalyzeReverseStream(channelPtrs, streamConfig);
        if (err != 0) lastError = err;
    }

    os_unfair_lock_unlock(&_lock);

    // Log errors if any
    if (lastError != 0 && (refCallCount <= 10 || refCallCount % 100 == 0)) {
        NSLog(@"AECBridge: REF ERROR - AnalyzeReverseStream returned %d", lastError);
    }

    // After processing enough reference frames, enable capture processing
    if (!_hasReceivedReference) {
        _referenceFramesPending--;
        if (_referenceFramesPending <= 0) {
            _hasReceivedReference = YES;
            NSLog(@"AECBridge: Reference audio established - enabling AEC on capture");
        }
    }
}

- (void)processCaptureFrame:(float *)samples count:(int)count {
    if (!_apm || !samples || count <= 0) return;

    // Only process if we have at least one full 10ms frame
    if (count < _expectedFrameSize) return;

    // Skip AEC processing until we've received reference audio
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

    // Log audio levels BEFORE processing to verify input format
    float preMinVal = 0, preMaxVal = 0, preSum = 0;
    if (capCallCount <= 5 || capCallCount % 500 == 0) {
        for (int i = 0; i < MIN(count, 480); i++) {
            float s = samples[i];
            if (s < preMinVal) preMinVal = s;
            if (s > preMaxVal) preMaxVal = s;
            preSum += fabsf(s);
        }
    }

    webrtc::StreamConfig streamConfig(_sampleRate, 1);  // mono

    // Process ALL complete 10ms frames to apply AEC to entire buffer
    int framesToProcess = count / _expectedFrameSize;

    // Lock to prevent concurrent access with AnalyzeReverseStream
    os_unfair_lock_lock(&_lock);

    // Set stream delay before processing
    _apm->set_stream_delay_ms(_streamDelayMs);

    int lastError = 0;
    for (int frame = 0; frame < framesToProcess; frame++) {
        float* channelPtr = samples + (frame * _expectedFrameSize);
        float* const* channelPtrs = &channelPtr;

        // ProcessStream modifies samples in-place with echo removed
        int err = _apm->ProcessStream(channelPtrs, streamConfig, streamConfig, channelPtrs);
        if (err != 0) lastError = err;
    }

    // Get AEC statistics
    webrtc::AudioProcessingStats stats = _apm->GetStatistics();

    os_unfair_lock_unlock(&_lock);

    // Log audio levels AFTER processing to see if AEC changed anything
    if (capCallCount <= 5 || capCallCount % 500 == 0) {
        float postMinVal = 0, postMaxVal = 0, postSum = 0;
        for (int i = 0; i < MIN(count, 480); i++) {
            float s = samples[i];
            if (s < postMinVal) postMinVal = s;
            if (s > postMaxVal) postMaxVal = s;
            postSum += fabsf(s);
        }
        float preAvg = preSum / MIN(count, 480);
        float postAvg = postSum / MIN(count, 480);
        float reduction = (preAvg > 0.0001f) ? ((preAvg - postAvg) / preAvg * 100.0f) : 0.0f;

        NSLog(@"AECBridge: CAP #%d - BEFORE: range=[%.4f,%.4f] avg=%.4f | AFTER: range=[%.4f,%.4f] avg=%.4f | reduction=%.1f%%",
              capCallCount, preMinVal, preMaxVal, preAvg, postMinVal, postMaxVal, postAvg, reduction);

        // Log AEC statistics
        if (stats.echo_return_loss.has_value()) {
            NSLog(@"AECBridge: AEC Stats - ERL=%.1fdB, ERLE=%.1fdB, divergent=%d",
                  stats.echo_return_loss.value_or(0),
                  stats.echo_return_loss_enhancement.value_or(0),
                  stats.divergent_filter_fraction.has_value() ? (int)(stats.divergent_filter_fraction.value() * 100) : -1);
        } else {
            NSLog(@"AECBridge: AEC Stats - No echo metrics available (AEC may not be detecting echo)");
        }
    }

    // Log errors if any
    if (lastError != 0 && (capCallCount <= 10 || capCallCount % 100 == 0)) {
        NSLog(@"AECBridge: CAP ERROR - ProcessStream returned %d", lastError);
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
