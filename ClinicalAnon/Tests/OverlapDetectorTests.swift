//
//  OverlapDetectorTests.swift
//  RedactorTests
//
//  Purpose: Unit tests for OverlapDetector
//  Organization: 3 Big Things
//

import XCTest
@testable import Redactor

final class OverlapDetectorTests: XCTestCase {

    var detector: OverlapDetector!

    override func setUp() {
        super.setUp()
        detector = OverlapDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    /// Create a test segment with minimal required fields
    private func segment(
        speaker: Speaker,
        start: TimeInterval,
        end: TimeInterval
    ) -> TranscriptSegment {
        TranscriptSegment(
            speaker: speaker,
            text: "Test text",
            startTime: start,
            endTime: end,
            chunkIndex: 0
        )
    }

    // MARK: - Basic Overlap Detection Tests

    func testDetectsSimpleOverlap() {
        // Mic: 0-5s, Sys: 3-8s -> Overlap at 3-5s (2 seconds)
        let mic = [segment(speaker: .clinician, start: 0, end: 5)]
        let sys = [segment(speaker: .other, start: 3, end: 8)]

        let result = detector.detectOverlaps(micSegments: mic, systemSegments: sys)

        XCTAssertEqual(result.overlaps.count, 1)
        XCTAssertEqual(result.overlaps[0].overlapDuration, 2.0, accuracy: 0.01)
        XCTAssertEqual(result.overlaps[0].startTime, 3.0, accuracy: 0.01)
        XCTAssertEqual(result.overlaps[0].endTime, 5.0, accuracy: 0.01)
    }

    func testNoFalsePositivesForNonOverlapping() {
        // Mic: 0-5s, Sys: 6-10s -> No overlap
        let mic = [segment(speaker: .clinician, start: 0, end: 5)]
        let sys = [segment(speaker: .other, start: 6, end: 10)]

        let result = detector.detectOverlaps(micSegments: mic, systemSegments: sys)

        XCTAssertTrue(result.overlaps.isEmpty)
    }

    func testAdjacentSegmentsNoOverlap() {
        // Mic: 0-5s, Sys: 5-10s -> Touching but not overlapping
        let mic = [segment(speaker: .clinician, start: 0, end: 5)]
        let sys = [segment(speaker: .other, start: 5, end: 10)]

        let result = detector.detectOverlaps(micSegments: mic, systemSegments: sys)

        XCTAssertTrue(result.overlaps.isEmpty)
    }

    func testMicContainedInSystem() {
        // Mic: 3-5s, Sys: 0-10s -> Overlap at 3-5s (mic is fully inside sys)
        let mic = [segment(speaker: .clinician, start: 3, end: 5)]
        let sys = [segment(speaker: .other, start: 0, end: 10)]

        let result = detector.detectOverlaps(micSegments: mic, systemSegments: sys)

        XCTAssertEqual(result.overlaps.count, 1)
        XCTAssertEqual(result.overlaps[0].overlapDuration, 2.0, accuracy: 0.01)
    }

    func testSystemContainedInMic() {
        // Mic: 0-10s, Sys: 3-5s -> Overlap at 3-5s (sys is fully inside mic)
        let mic = [segment(speaker: .clinician, start: 0, end: 10)]
        let sys = [segment(speaker: .other, start: 3, end: 5)]

        let result = detector.detectOverlaps(micSegments: mic, systemSegments: sys)

        XCTAssertEqual(result.overlaps.count, 1)
        XCTAssertEqual(result.overlaps[0].overlapDuration, 2.0, accuracy: 0.01)
    }

    // MARK: - Multiple Segment Tests

    func testMultipleOverlaps() {
        // Mic: 0-3s, 5-8s; Sys: 2-6s -> Two overlaps
        let mic = [
            segment(speaker: .clinician, start: 0, end: 3),
            segment(speaker: .clinician, start: 5, end: 8)
        ]
        let sys = [segment(speaker: .other, start: 2, end: 6)]

        let result = detector.detectOverlaps(micSegments: mic, systemSegments: sys)

        XCTAssertEqual(result.overlaps.count, 2)
    }

    func testNoOverlapsWithEmptyInput() {
        let result1 = detector.detectOverlaps(micSegments: [], systemSegments: [])
        XCTAssertTrue(result1.overlaps.isEmpty)

        let mic = [segment(speaker: .clinician, start: 0, end: 5)]
        let result2 = detector.detectOverlaps(micSegments: mic, systemSegments: [])
        XCTAssertTrue(result2.overlaps.isEmpty)

        let sys = [segment(speaker: .other, start: 0, end: 5)]
        let result3 = detector.detectOverlaps(micSegments: [], systemSegments: sys)
        XCTAssertTrue(result3.overlaps.isEmpty)
    }

    // MARK: - Annotation Tests

    func testSegmentsAnnotatedWithOverlap() {
        let mic = [segment(speaker: .clinician, start: 0, end: 5)]
        let sys = [segment(speaker: .other, start: 3, end: 8)]

        let result = detector.detectOverlaps(micSegments: mic, systemSegments: sys)

        // Both segments should be marked as having overlap
        let annotatedMic = result.annotatedSegments.first { $0.speaker == .clinician }
        let annotatedSys = result.annotatedSegments.first { $0.speaker == .other }

        XCTAssertTrue(annotatedMic?.hasOverlap ?? false)
        XCTAssertTrue(annotatedSys?.hasOverlap ?? false)
    }

    func testNonOverlappingSegmentsNotAnnotated() {
        let mic = [segment(speaker: .clinician, start: 0, end: 5)]
        let sys = [segment(speaker: .other, start: 10, end: 15)]

        let result = detector.detectOverlaps(micSegments: mic, systemSegments: sys)

        // Neither segment should be marked as overlapping
        for segment in result.annotatedSegments {
            XCTAssertFalse(segment.hasOverlap)
        }
    }

    // MARK: - Minimum Duration Threshold Tests

    func testVeryShortOverlapIgnored() {
        detector.minimumOverlapDuration = 0.1

        // Mic: 0-5s, Sys: 4.95-10s -> Overlap of only 0.05s should be ignored
        let mic = [segment(speaker: .clinician, start: 0, end: 5)]
        let sys = [segment(speaker: .other, start: 4.95, end: 10)]

        let result = detector.detectOverlaps(micSegments: mic, systemSegments: sys)

        XCTAssertTrue(result.overlaps.isEmpty)
    }

    func testOverlapAtExactThreshold() {
        detector.minimumOverlapDuration = 0.1

        // Mic: 0-0.4s, Sys: 0.3-0.7s -> Overlap of 0.1s (25% of each segment) should be detected
        let mic = [segment(speaker: .clinician, start: 0, end: 0.4)]
        let sys = [segment(speaker: .other, start: 0.3, end: 0.7)]

        let result = detector.detectOverlaps(micSegments: mic, systemSegments: sys)

        XCTAssertEqual(result.overlaps.count, 1)
    }

    // MARK: - Annotate Overlaps Convenience Method

    func testAnnotateOverlapsMixedSegments() {
        let segments = [
            segment(speaker: .clinician, start: 0, end: 5),
            segment(speaker: .other, start: 3, end: 8),
            segment(speaker: .clinician, start: 10, end: 15)
        ]

        let annotated = detector.annotateOverlaps(segments: segments)

        XCTAssertEqual(annotated.count, 3)

        // First two should have overlap
        let firstClinician = annotated.first { $0.startTime == 0 }
        XCTAssertTrue(firstClinician?.hasOverlap ?? false)

        let other = annotated.first { $0.speaker == .other }
        XCTAssertTrue(other?.hasOverlap ?? false)

        // Third should not have overlap
        let secondClinician = annotated.first { $0.startTime == 10 }
        XCTAssertFalse(secondClinician?.hasOverlap ?? true)
    }

    // MARK: - Performance Tests

    func testPerformanceWithManySegments() {
        // Create 100 segments for each speaker
        var micSegments: [TranscriptSegment] = []
        var sysSegments: [TranscriptSegment] = []

        for i in 0..<100 {
            let start = TimeInterval(i * 10)
            micSegments.append(segment(speaker: .clinician, start: start, end: start + 8))
            sysSegments.append(segment(speaker: .other, start: start + 5, end: start + 13))
        }

        measure {
            _ = detector.detectOverlaps(micSegments: micSegments, systemSegments: sysSegments)
        }
    }
}
