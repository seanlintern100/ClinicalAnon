//
//  OverlapDetector.swift
//  ClinicalAnon
//
//  Purpose: Detects overlapping speech between microphone and system audio streams
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Overlap Annotation

/// Represents a detected overlap between two speech segments
struct OverlapAnnotation: Identifiable {
    let id = UUID()

    /// Start time of the overlap (in seconds from session start)
    let startTime: TimeInterval

    /// End time of the overlap
    let endTime: TimeInterval

    /// ID of the microphone segment involved in the overlap
    let micSegmentId: UUID

    /// ID of the system audio segment involved in the overlap
    let systemSegmentId: UUID

    /// Duration of the overlap in seconds
    var overlapDuration: TimeInterval {
        endTime - startTime
    }

    /// Whether this is a significant overlap (> 0.5 seconds)
    var isSignificant: Bool {
        overlapDuration > 0.5
    }
}

// MARK: - Overlap Detection Result

/// Result of overlap detection for a chunk
struct OverlapDetectionResult {
    /// Detected overlaps
    let overlaps: [OverlapAnnotation]

    /// Segments with overlap flags updated
    let annotatedSegments: [TranscriptSegment]

    /// Total overlap duration in this chunk
    var totalOverlapDuration: TimeInterval {
        overlaps.reduce(0) { $0 + $1.overlapDuration }
    }

    /// Number of significant overlaps (> 0.5s)
    var significantOverlapCount: Int {
        overlaps.filter { $0.isSignificant }.count
    }
}

// MARK: - Overlap Detector

/// Detects overlapping segments between microphone and system audio streams
class OverlapDetector {

    // MARK: - Configuration

    /// Minimum overlap duration to consider (in seconds)
    /// Overlaps shorter than this are ignored as they may be timing noise
    var minimumOverlapDuration: TimeInterval = 0.1

    // MARK: - Public Methods

    /// Detect overlaps between microphone and system audio segments
    /// - Parameters:
    ///   - micSegments: Segments from microphone audio (clinician)
    ///   - systemSegments: Segments from system audio (other participants)
    /// - Returns: Overlap detection result with annotations and updated segments
    func detectOverlaps(
        micSegments: [TranscriptSegment],
        systemSegments: [TranscriptSegment]
    ) -> OverlapDetectionResult {
        var overlaps: [OverlapAnnotation] = []
        var micOverlapMap: [UUID: [UUID]] = [:]  // mic segment ID -> overlapping system segment IDs
        var sysOverlapMap: [UUID: [UUID]] = [:]  // sys segment ID -> overlapping mic segment IDs

        // Check each mic segment against each system segment
        for micSegment in micSegments {
            for sysSegment in systemSegments {
                // Check if segments overlap in time
                // Overlap occurs when: mic.start < sys.end AND mic.end > sys.start
                if micSegment.startTime < sysSegment.endTime && micSegment.endTime > sysSegment.startTime {
                    // Calculate overlap bounds
                    let overlapStart = max(micSegment.startTime, sysSegment.startTime)
                    let overlapEnd = min(micSegment.endTime, sysSegment.endTime)
                    let overlapDuration = overlapEnd - overlapStart

                    // Only count if overlap is significant enough
                    if overlapDuration >= minimumOverlapDuration {
                        let annotation = OverlapAnnotation(
                            startTime: overlapStart,
                            endTime: overlapEnd,
                            micSegmentId: micSegment.id,
                            systemSegmentId: sysSegment.id
                        )
                        overlaps.append(annotation)

                        // Track which segments overlap with which
                        micOverlapMap[micSegment.id, default: []].append(sysSegment.id)
                        sysOverlapMap[sysSegment.id, default: []].append(micSegment.id)
                    }
                }
            }
        }

        // Create annotated segments with overlap info
        var annotatedSegments: [TranscriptSegment] = []

        for segment in micSegments {
            let overlappingIds = micOverlapMap[segment.id] ?? []
            let annotated = TranscriptSegment(
                id: segment.id,
                speaker: segment.speaker,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                chunkIndex: segment.chunkIndex,
                confidence: segment.confidence,
                hasOverlap: !overlappingIds.isEmpty,
                overlappingSegmentIds: overlappingIds,
                speakerId: segment.speakerId,
                speakerConfidence: segment.speakerConfidence
            )
            annotatedSegments.append(annotated)
        }

        for segment in systemSegments {
            let overlappingIds = sysOverlapMap[segment.id] ?? []
            let annotated = TranscriptSegment(
                id: segment.id,
                speaker: segment.speaker,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                chunkIndex: segment.chunkIndex,
                confidence: segment.confidence,
                hasOverlap: !overlappingIds.isEmpty,
                overlappingSegmentIds: overlappingIds,
                speakerId: segment.speakerId,
                speakerConfidence: segment.speakerConfidence
            )
            annotatedSegments.append(annotated)
        }

        // Sort by start time
        annotatedSegments.sort { $0.startTime < $1.startTime }

        return OverlapDetectionResult(
            overlaps: overlaps,
            annotatedSegments: annotatedSegments
        )
    }

    /// Annotate existing segments with overlap information
    /// This is a lighter-weight version that just updates existing segments
    /// - Parameter segments: All transcript segments (mixed speakers)
    /// - Returns: Segments with overlap flags set
    func annotateOverlaps(segments: [TranscriptSegment]) -> [TranscriptSegment] {
        // Separate by speaker
        let micSegments = segments.filter { $0.speaker == .clinician }
        let sysSegments = segments.filter { $0.speaker == .other }

        // Detect overlaps
        let result = detectOverlaps(micSegments: micSegments, systemSegments: sysSegments)

        return result.annotatedSegments
    }
}
