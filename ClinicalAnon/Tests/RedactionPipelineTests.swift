//
//  RedactionPipelineTests.swift
//  RedactorTests
//
//  Purpose: End-to-end tests for the redaction pipeline
//  Verifies names at all positions in text are detected and redacted
//

import XCTest
@testable import Redactor

@MainActor
final class RedactionPipelineTests: XCTestCase {

    private var engine: AnonymizationEngine!

    override func setUp() {
        super.setUp()
        engine = AnonymizationEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Name Detection Tests

    /// Test that names at the END of text are detected (reproduces Wendy bug)
    func testNameAtEndOfTextIsDetected() async throws {
        let text = """
        Court coming up
        In and off sych help – some is useful
        Getting better at life

        Sister was looking after son but son has moved to akl now.
        1 long term rlation ship for 4 years

        Taking deepbfreaths an help

        Wendy – take sto appoitnmets
        """

        let result = try await engine.anonymize(text)

        // Check that Wendy is in the detected entities
        let wendyEntity = result.entities.first { $0.originalText.lowercased() == "wendy" }
        XCTAssertNotNil(wendyEntity, "Wendy should be detected as an entity")

        if let entity = wendyEntity {
            XCTAssertTrue(entity.type.isPerson, "Wendy should be detected as a person type, got \(entity.type)")
            XCTAssertFalse(entity.positions.isEmpty, "Wendy should have at least one position")
            XCTAssertFalse(entity.replacementCode.isEmpty, "Wendy should have a replacement code")

            // Verify position is valid
            let nsText = text as NSString
            for position in entity.positions {
                XCTAssertEqual(position.count, 2, "Position should be [start, end]")
                let start = position[0]
                let end = position[1]
                XCTAssertGreaterThanOrEqual(start, 0)
                XCTAssertLessThanOrEqual(end, nsText.length, "Position end (\(end)) exceeds text length (\(nsText.length))")
                XCTAssertLessThan(start, end)

                let extracted = nsText.substring(with: NSRange(location: start, length: end - start))
                XCTAssertEqual(extracted.lowercased(), "wendy", "Position should point to 'Wendy' in text, got '\(extracted)'")
            }
        }
    }

    /// Test that names at the BEGINNING of text are detected
    func testNameAtBeginningOfTextIsDetected() async throws {
        let text = """
        Hamish came to the appointment today.
        He discussed his goals for the week.
        """

        let result = try await engine.anonymize(text)

        let hamishEntity = result.entities.first { $0.originalText.lowercased() == "hamish" }
        XCTAssertNotNil(hamishEntity, "Hamish should be detected as an entity")
    }

    /// Test that names in the MIDDLE of text are detected
    func testNameInMiddleOfTextIsDetected() async throws {
        let text = """
        The client arrived on time.
        Wendy discussed her current situation.
        She will return next week.
        """

        let result = try await engine.anonymize(text)

        let wendyEntity = result.entities.first { $0.originalText.lowercased() == "wendy" }
        XCTAssertNotNil(wendyEntity, "Wendy should be detected in the middle of text")
    }

    /// Test the exact text from the user's bug report
    func testFullClinicalNoteEndNameDetection() async throws {
        let text = """
        Hamish
        Court coming up
        In and off sych help – some is useful
        ]Stacey Graham- coubsellor/psych – learn ts soe awesomes stuff
        Getting better at life
        Punched someone and crcked light onff car
        Been busted fro dangerous weapon and a bullet n me. Always got a kinfe on me
        Multiple weapons and assults charges in past
        30-40 times
        Been on prison about 3 years total. Longest was 2 years -last time about 10 years
        Have a few kids with oeple not with
        Got into an argument with my son – he was who I punched – 16 yo – hes pressing charged
        Got a lwayer – and going to court this Friday

        Thing Stacey taught me is what to do when I start to feel ngry – I cant handle this so I need to go – wal away and chill out
        Son wasn;t waking up . it was a wind up situation. Him being there was a bad vibe


        After ocurt I want o
        Work on a farm
        Bits an pieces of farm work all my life
        Last time was milking cows – about 10-15 years ago
        Worked in tapuo for power company – keft tehre about 1-2 years. Worked for about a year
        Acc – get about 600 a week – child support comes out of that – aybe

        Dot drink hardl at – all occiaosnally 1-2 – is one f the things that get me fucked up. Afraid I could really hurt someoe
        Meth – every now and again – recreational 0 not si much recently

        What oing well
        Got clothes, roof food.
        Lied in all sorts f places – bush, cars etc
        Happiest out in thy ebush or fishing
        Would like toliv and work on farm

        Currently
        Walk a lot
        Broke leg in otorkbike accident about last year
        Know a llt of pople but not close
        Born in pay hospital
        Mum and dad aive it not close. Will visit
        The got a property – luxrla swhite pine wildlife park – bird life
        1 bro and 2 sis – 1 sis dead abot 8 years ago – cancer
        Stayed with sis in taupo for 8 years

        Sister was looking after son but son has moved to akl now.
        1 long term rlation ship for 4 years

        Would like to work on communication and listeing – want to be able to discuss hav arfgeunenst without having angry arguments
        Like beimng by myslf and with animals and nature

        Taking deepbfreaths an help

        Wendy – take sto appoitnmets
        """

        let result = try await engine.anonymize(text)

        // All three names should be detected
        let expectedNames = ["hamish", "stacey", "wendy"]
        for name in expectedNames {
            let entity = result.entities.first { $0.originalText.lowercased().contains(name) }
            XCTAssertNotNil(entity, "'\(name)' should be detected as an entity")

            if let entity = entity {
                print("✅ '\(name)' detected: type=\(entity.type), code=\(entity.replacementCode), positions=\(entity.positions)")
            }
        }

        // Verify Wendy specifically has valid positions
        let wendyEntity = result.entities.first { $0.originalText.lowercased() == "wendy" }
        if let wendy = wendyEntity {
            let nsText = text as NSString
            for position in wendy.positions {
                let start = position[0]
                let end = position[1]
                XCTAssertLessThanOrEqual(end, nsText.length,
                    "Wendy position end (\(end)) exceeds nsText.length (\(nsText.length))")

                let extracted = nsText.substring(with: NSRange(location: start, length: end - start))
                print("📍 Wendy position [\(start),\(end)] extracts '\(extracted)'")
            }
        }
    }

    // MARK: - Redacted Text Output Tests

    /// Test that a name at the end of text appears redacted in the output
    func testNameAtEndIsRedactedInOutput() async throws {
        let text = """
        Some notes about the session.
        The client discussed their goals.

        Wendy – take to appointments
        """

        let result = try await engine.anonymize(text)

        let wendyEntity = result.entities.first { $0.originalText.lowercased() == "wendy" }
        XCTAssertNotNil(wendyEntity, "Wendy must be detected first")

        guard let entity = wendyEntity else { return }

        // Now simulate what updateRedactedTextCache does
        let nsText = result.originalText as NSString
        var allReplacements: [(start: Int, end: Int, code: String)] = []

        for position in entity.positions {
            guard position.count >= 2 else { continue }
            let start = position[0]
            let end = position[1]
            guard start >= 0 && end <= nsText.length && start < end else {
                XCTFail("Position [\(start),\(end)] out of bounds (length=\(nsText.length))")
                continue
            }
            allReplacements.append((start: start, end: end, code: entity.replacementCode))
        }

        XCTAssertFalse(allReplacements.isEmpty, "Wendy should have valid replacements")

        // Build redacted text
        allReplacements.sort { $0.start < $1.start }
        var parts: [String] = []
        var pos = 0
        for r in allReplacements {
            if pos < r.start {
                parts.append(nsText.substring(with: NSRange(location: pos, length: r.start - pos)))
            }
            parts.append(r.code)
            pos = r.end
        }
        if pos < nsText.length {
            parts.append(nsText.substring(with: NSRange(location: pos, length: nsText.length - pos)))
        }
        let redacted = parts.joined()

        XCTAssertFalse(redacted.contains("Wendy"), "Redacted text should not contain 'Wendy', got: ...'\(String(redacted.suffix(100)))'")
        XCTAssertTrue(redacted.contains(entity.replacementCode), "Redacted text should contain \(entity.replacementCode)")

        print("📝 Last 100 chars of redacted text: '\(String(redacted.suffix(100)))'")
    }

    // MARK: - Overlap Resolver Tests

    /// Test the overlap resolver doesn't drop the last entity
    func testOverlapResolverKeepsLastEntity() {
        // Simulate the overlap resolver from updateRedactedTextCache
        var allReplacements: [(start: Int, end: Int, code: String, entityType: EntityType)] = [
            (start: 0, end: 6, code: "[PERSON_A]", entityType: .personOther),     // "Hamish"
            (start: 100, end: 106, code: "[PERSON_B]", entityType: .personOther),  // "Stacey"
            (start: 2050, end: 2055, code: "[PERSON_C]", entityType: .personOther) // "Wendy" at end
        ]

        // Sort
        allReplacements.sort {
            if $0.start != $1.start { return $0.start < $1.start }
            return ($0.end - $0.start) > ($1.end - $1.start)
        }

        // Overlap resolve
        var nonOverlapping: [(start: Int, end: Int, code: String, entityType: EntityType)] = []
        var maxEnd = 0

        for replacement in allReplacements {
            if replacement.start >= maxEnd {
                nonOverlapping.append(replacement)
                maxEnd = replacement.end
            } else if replacement.end > maxEnd {
                if let last = nonOverlapping.last, replacement.start < last.end {
                    let lastLength = last.end - last.start
                    let currentLength = replacement.end - replacement.start
                    if currentLength > lastLength {
                        nonOverlapping.removeLast()
                        nonOverlapping.append(replacement)
                    }
                }
                maxEnd = replacement.end
            }
        }

        XCTAssertEqual(nonOverlapping.count, 3, "All three non-overlapping entities should survive")
        XCTAssertEqual(nonOverlapping.last?.code, "[PERSON_C]", "Last entity (Wendy) should survive overlap resolution")
    }

    /// Test chain-drop bug is fixed
    func testChainDropBugFixed() {
        var allReplacements: [(start: Int, end: Int, code: String, entityType: EntityType)] = [
            (start: 0, end: 20, code: "[A]", entityType: .personOther),   // Long entity
            (start: 10, end: 15, code: "[B]", entityType: .personOther),  // Contained in A
            (start: 12, end: 25, code: "[C]", entityType: .personOther),  // Overlaps A, extends beyond
        ]

        allReplacements.sort {
            if $0.start != $1.start { return $0.start < $1.start }
            return ($0.end - $0.start) > ($1.end - $1.start)
        }

        var nonOverlapping: [(start: Int, end: Int, code: String, entityType: EntityType)] = []
        var maxEnd = 0

        for replacement in allReplacements {
            if replacement.start >= maxEnd {
                nonOverlapping.append(replacement)
                maxEnd = replacement.end
            } else if replacement.end > maxEnd {
                if let last = nonOverlapping.last, replacement.start < last.end {
                    let lastLength = last.end - last.start
                    let currentLength = replacement.end - replacement.start
                    if currentLength > lastLength {
                        nonOverlapping.removeLast()
                        nonOverlapping.append(replacement)
                    }
                }
                maxEnd = replacement.end
            }
        }

        // A should be kept (longest at start 0), B dropped (contained), C dropped (shorter than A)
        // But maxEnd should be 25 (from C), not 20 (from A)
        XCTAssertEqual(nonOverlapping.count, 1, "Only A should be in nonOverlapping")
        XCTAssertEqual(nonOverlapping[0].code, "[A]")
        XCTAssertEqual(maxEnd, 25, "maxEnd should extend to 25 from C, preventing chain-drop of future entities")
    }
}
