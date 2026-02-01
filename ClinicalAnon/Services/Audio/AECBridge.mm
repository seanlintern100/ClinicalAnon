//
//  AECBridge.mm
//  ClinicalAnon
//
//  Purpose: Lightweight echo cancellation using simple spectral subtraction
//  Designed for minimal CPU impact during real-time recording
//

#import "AECBridge.h"
#import <Accelerate/Accelerate.h>
#import <atomic>

// Simple ring buffer for reference audio
static const int kRingBufferSize = 48000;  // 1 second at 48kHz

@implementation AECBridge {
    int _sampleRate;
    int _streamDelayMs;
    int _delaySamples;

    // Lock-free ring buffer for reference signal
    float _referenceRing[kRingBufferSize];
    std::atomic<int> _refWriteIdx;
    std::atomic<int> _refAvailable;

    // Simple echo estimation
    float _refPowerEstimate;
    float _echoAttenuation;

    BOOL _isActive;
}

- (instancetype)initWithSampleRate:(int)sampleRate {
    self = [super init];
    if (self) {
        _sampleRate = sampleRate;
        _streamDelayMs = 50;
        _delaySamples = (sampleRate * _streamDelayMs) / 1000;

        // Initialize ring buffer
        memset(_referenceRing, 0, sizeof(_referenceRing));
        _refWriteIdx = 0;
        _refAvailable = 0;

        _refPowerEstimate = 0.0f;
        _echoAttenuation = 0.8f;  // Strong attenuation to suppress speaker bleed

        _isActive = YES;

        NSLog(@"AECBridge: Lightweight AEC initialized at %d Hz", sampleRate);
    }
    return self;
}

- (void)processReferenceFrame:(const float *)samples count:(int)count {
    if (!samples || count <= 0) return;

    // Lock-free write to ring buffer
    int writeIdx = _refWriteIdx.load(std::memory_order_relaxed);

    for (int i = 0; i < count; i++) {
        _referenceRing[writeIdx] = samples[i];
        writeIdx = (writeIdx + 1) % kRingBufferSize;
    }

    _refWriteIdx.store(writeIdx, std::memory_order_release);

    // Update reference power estimate (simple exponential moving average)
    float framePower = 0.0f;
    int sampleCount = MIN(count, 256);  // Only check first 256 samples
    for (int i = 0; i < sampleCount; i++) {
        framePower += samples[i] * samples[i];
    }
    framePower /= sampleCount;

    // Smooth power estimate
    _refPowerEstimate = 0.95f * _refPowerEstimate + 0.05f * framePower;
}

- (void)processCaptureFrame:(float *)samples count:(int)count {
    if (!samples || count <= 0 || !_isActive) return;

    // Skip processing if no reference audio (nothing playing through speakers)
    if (_refPowerEstimate < 0.00001f) {
        return;  // No modification needed - no echo expected
    }

    // Calculate mic frame power to detect if clinician is speaking
    float micFramePower = 0.0f;
    int sampleCount = MIN(count, 256);
    for (int i = 0; i < sampleCount; i++) {
        micFramePower += samples[i] * samples[i];
    }
    micFramePower /= sampleCount;

    // When system audio is significantly louder than expected clinician voice,
    // assume the mic is picking up mostly speaker bleed and attenuate heavily
    int writeIdx = _refWriteIdx.load(std::memory_order_acquire);

    for (int i = 0; i < count; i++) {
        // Get delayed reference sample (try multiple delays to catch varying acoustic paths)
        int refIdx = (writeIdx - _delaySamples - (count - i) + kRingBufferSize * 2) % kRingBufferSize;
        float refSample = _referenceRing[refIdx];

        // Also check slightly earlier and later delays
        int refIdxEarly = (refIdx + 480 + kRingBufferSize) % kRingBufferSize;  // +10ms
        int refIdxLate = (refIdx - 480 + kRingBufferSize) % kRingBufferSize;   // -10ms
        float refSampleEarly = _referenceRing[refIdxEarly];
        float refSampleLate = _referenceRing[refIdxLate];

        // Use the maximum reference energy across delay range
        float maxRef = fmaxf(fabsf(refSample), fmaxf(fabsf(refSampleEarly), fabsf(refSampleLate)));

        float micSample = samples[i];

        // Only attenuate if reference has significant energy
        if (maxRef > 0.001f) {
            // Subtract estimated echo (scaled reference)
            // Use the reference sample closest in time
            float echoEstimate = refSample * _echoAttenuation;
            samples[i] = micSample - echoEstimate;

            // Additionally attenuate mic when system audio is loud
            // This helps when the delay estimation is off
            if (_refPowerEstimate > 0.001f) {
                float suppressionFactor = fminf(1.0f, 0.3f / sqrtf(_refPowerEstimate + 0.0001f));
                samples[i] *= suppressionFactor;
            }

            // Soft clip to prevent artifacts
            if (samples[i] > 1.0f) samples[i] = 1.0f;
            if (samples[i] < -1.0f) samples[i] = -1.0f;
        }
    }
}

- (void)setStreamDelayMs:(int)delayMs {
    _streamDelayMs = MAX(0, MIN(delayMs, 200));
    _delaySamples = (_sampleRate * _streamDelayMs) / 1000;
    NSLog(@"AECBridge: Delay set to %d ms", _streamDelayMs);
}

- (BOOL)isActive {
    return _isActive;
}

- (void)reset {
    memset(_referenceRing, 0, sizeof(_referenceRing));
    _refWriteIdx = 0;
    _refAvailable = 0;
    _refPowerEstimate = 0.0f;
    NSLog(@"AECBridge: Reset");
}

@end
