//
//  RedactPhaseStateIntegrationTests.swift
//  RedactorTests
//
//  Purpose: Integration tests exercising the full app redaction path:
//  RedactPhaseState.analyze() → updateRedactedTextCache() → displayedRedactedText
//  These reproduce the Wendy-at-end-of-text bug that unit tests missed.
//

import XCTest
@testable import Redactor

@MainActor
final class RedactPhaseStateIntegrationTests: XCTestCase {

    private var engine: AnonymizationEngine!
    private var state: RedactPhaseState!

    override func setUp() {
        super.setUp()
        engine = AnonymizationEngine()
        state = RedactPhaseState(engine: engine)
    }

    override func tearDown() {
        state = nil
        engine = nil
        super.tearDown()
    }

    // MARK: - End-to-End Redacted Output Tests

    /// Name on the LAST LINE must be redacted in displayed text
    func testNameAtEndIsRedactedInDisplayedText() async throws {
        state.inputText = """
        Some notes about the session.
        The client discussed their goals.

        Wendy – take to appointments
        """

        await state.analyze()

        let displayed = state.displayedRedactedText
        XCTAssertFalse(
            displayed.contains("Wendy"),
            "displayedRedactedText should NOT contain 'Wendy' — last 100 chars: '\(String(displayed.suffix(100)))'"
        )
        XCTAssertTrue(
            displayed.contains("[PERSON_"),
            "displayedRedactedText should contain a [PERSON_] replacement code"
        )
    }

    /// Full clinical note: ALL names must be redacted in displayed text
    func testFullClinicalNoteEndNameRedacted() async throws {
        state.inputText = """
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

        await state.analyze()

        let displayed = state.displayedRedactedText

        // All three names must be absent from displayed text
        let namesExpectedRedacted = ["Hamish", "Stacey", "Wendy"]
        for name in namesExpectedRedacted {
            XCTAssertFalse(
                displayed.contains(name),
                "'\(name)' should be redacted in displayedRedactedText — last 200 chars: '\(String(displayed.suffix(200)))'"
            )
        }
    }

    /// Name at the BEGINNING of text (control — expected to pass)
    func testNameAtBeginningIsRedactedInDisplayedText() async throws {
        state.inputText = """
        Hamish came to the appointment today.
        He discussed his goals for the week.
        """

        await state.analyze()

        let displayed = state.displayedRedactedText
        XCTAssertFalse(
            displayed.contains("Hamish"),
            "displayedRedactedText should NOT contain 'Hamish'"
        )
    }

    /// Name in the MIDDLE of text (control — expected to pass)
    func testNameInMiddleIsRedactedInDisplayedText() async throws {
        state.inputText = """
        The client arrived on time.
        Wendy discussed her current situation.
        She will return next week.
        """

        await state.analyze()

        let displayed = state.displayedRedactedText
        XCTAssertFalse(
            displayed.contains("Wendy"),
            "displayedRedactedText should NOT contain 'Wendy'"
        )
    }

    // MARK: - Diagnostic Tests

    /// Verify the entity survives into activeEntities with valid positions
    func testActiveEntitiesContainsEndName() async throws {
        state.inputText = """
        Some notes about the session.
        The client discussed their goals.

        Wendy – take sto appoitnmets
        """

        await state.analyze()

        // Check result exists
        XCTAssertNotNil(state.result, "Result should be set after analyze()")

        // Check Wendy is in activeEntities
        let wendyEntity = state.activeEntities.first { $0.originalText.lowercased() == "wendy" }
        XCTAssertNotNil(wendyEntity, "Wendy should be in activeEntities after analyze()")

        if let entity = wendyEntity {
            XCTAssertTrue(entity.type.isPerson, "Wendy should be person type, got \(entity.type)")
            XCTAssertFalse(entity.positions.isEmpty, "Wendy should have positions")
            XCTAssertFalse(entity.replacementCode.isEmpty, "Wendy should have a replacement code")

            // Validate positions against original text
            let nsText = state.result!.originalText as NSString
            for position in entity.positions {
                XCTAssertEqual(position.count, 2, "Position should be [start, end]")
                let start = position[0]
                let end = position[1]
                XCTAssertGreaterThanOrEqual(start, 0, "Position start should be >= 0")
                XCTAssertLessThanOrEqual(end, nsText.length, "Position end (\(end)) exceeds nsText.length (\(nsText.length))")
                XCTAssertLessThan(start, end, "Position start should be < end")

                let extracted = nsText.substring(with: NSRange(location: start, length: end - start))
                print("📍 Wendy position [\(start),\(end)] extracts '\(extracted)'")
            }
        }
    }

    /// Name at end with trailing whitespace/newlines (simulates paste from clipboard)
    func testNameAtEndWithTrailingWhitespace() async throws {
        // Simulate text that might come from clipboard paste — trailing newlines
        state.inputText = "Some notes about the session.\nThe client discussed their goals.\n\nWendy – take to appointments\n\n  \n"

        await state.analyze()

        let displayed = state.displayedRedactedText
        XCTAssertFalse(
            displayed.contains("Wendy"),
            "Wendy should be redacted even with trailing whitespace — last 100 chars: '\(String(displayed.suffix(100)))'"
        )
    }

    /// Name at end with NO trailing newline (edge case)
    func testNameAtEndNoTrailingNewline() async throws {
        state.inputText = "Some notes.\n\nWendy – take to appointments"

        await state.analyze()

        let displayed = state.displayedRedactedText
        XCTAssertFalse(
            displayed.contains("Wendy"),
            "Wendy should be redacted with no trailing newline — text: '\(displayed)'"
        )
    }

    /// THE BUG: \r\n line endings cause text.count != NSString.length,
    /// making ChunkManager.contentEnd too small and filtering entities at end of text
    func testNameAtEndWithCRLFLineEndings() async throws {
        // Simulate text pasted from Windows/rich text with \r\n line endings
        state.inputText = "Hamish\r\nCourt coming up\r\nIn and off sych help – some is useful\r\n\r\nSister was looking after son but son has moved to akl now.\r\n1 long term rlation ship for 4 years\r\n\r\nTaking deepbfreaths an help\r\n\r\nWendy – take sto appoitnmets\r\n"

        await state.analyze()

        // Verify both names are detected
        let wendyEntity = state.activeEntities.first { $0.originalText.lowercased() == "wendy" }
        XCTAssertNotNil(wendyEntity, "Wendy must be detected even with \\r\\n line endings")

        let hamishEntity = state.activeEntities.first { $0.originalText.lowercased() == "hamish" }
        XCTAssertNotNil(hamishEntity, "Hamish must be detected with \\r\\n line endings")

        // Verify redacted text doesn't contain either name
        let displayed = state.displayedRedactedText
        XCTAssertFalse(
            displayed.contains("Wendy"),
            "Wendy should be redacted with \\r\\n line endings — last 100 chars: '\(String(displayed.suffix(100)))'"
        )
        XCTAssertFalse(
            displayed.contains("Hamish"),
            "Hamish should be redacted with \\r\\n line endings"
        )
    }

    /// Full clinical note with \r\n endings — reproduces the exact user bug
    func testFullClinicalNoteCRLFEndNameRedacted() async throws {
        state.inputText = "Hamish\r\nCourt coming up\r\nIn and off sych help – some is useful\r\n]Stacey Graham- coubsellor/psych – learn ts soe awesomes stuff\r\nGetting better at life\r\nPunched someone and crcked light onff car\r\nBeen busted fro dangerous weapon and a bullet n me. Always got a kinfe on me\r\nMultiple weapons and assults charges in past\r\n30-40 times\r\nBeen on prison about 3 years total. Longest was 2 years -last time about 10 years\r\nHave a few kids with oeple not with\r\nGot into an argument with my son – he was who I punched – 16 yo – hes pressing charged\r\nGot a lwayer – and going to court this Friday\r\n\r\nThing Stacey taught me is what to do when I start to feel ngry – I cant handle this so I need to go – wal away and chill out\r\nSon wasn;t waking up . it was a wind up situation. Him being there was a bad vibe\r\n\r\n\r\nAfter ocurt I want o\r\nWork on a farm\r\nBits an pieces of farm work all my life\r\nLast time was milking cows – about 10-15 years ago\r\nWorked in tapuo for power company – keft tehre about 1-2 years. Worked for about a year\r\nAcc – get about 600 a week – child support comes out of that – aybe\r\n\r\nDot drink hardl at – all occiaosnally 1-2 – is one f the things that get me fucked up. Afraid I could really hurt someoe\r\nMeth – every now and again – recreational 0 not si much recently\r\n\r\nWhat oing well\r\nGot clothes, roof food.\r\nLied in all sorts f places – bush, cars etc\r\nHappiest out in thy ebush or fishing\r\nWould like toliv and work on farm\r\n\r\nCurrently\r\nWalk a lot\r\nBroke leg in otorkbike accident about last year\r\nKnow a llt of pople but not close\r\nBorn in pay hospital\r\nMum and dad aive it not close. Will visit\r\nThe got a property – luxrla swhite pine wildlife park – bird life\r\n1 bro and 2 sis – 1 sis dead abot 8 years ago – cancer\r\nStayed with sis in taupo for 8 years\r\n\r\nSister was looking after son but son has moved to akl now.\r\n1 long term rlation ship for 4 years\r\n\r\nWould like to work on communication and listeing – want to be able to discuss hav arfgeunenst without having angry arguments\r\nLike beimng by myslf and with animals and nature\r\n\r\nTaking deepbfreaths an help\r\n\r\nWendy – take sto appoitnmets\r\n"

        await state.analyze()

        let displayed = state.displayedRedactedText

        for name in ["Hamish", "Stacey", "Wendy"] {
            XCTAssertFalse(
                displayed.contains(name),
                "'\(name)' should be redacted with \\r\\n line endings — last 200 chars: '\(String(displayed.suffix(200)))'"
            )
        }
    }

    /// Validate ALL entity positions from a full clinical note analysis
    func testAllReplacementPositionsAreValid() async throws {
        state.inputText = """
        Hamish
        Court coming up
        In and off sych help – some is useful

        Sister was looking after son but son has moved to akl now.
        1 long term rlation ship for 4 years

        Taking deepbfreaths an help

        Wendy – take sto appoitnmets
        """

        await state.analyze()

        guard let result = state.result else {
            XCTFail("Result should be set after analyze()")
            return
        }

        let nsText = result.originalText as NSString
        var totalPositions = 0
        var invalidPositions = 0

        for entity in state.activeEntities {
            for position in entity.positions {
                totalPositions += 1
                guard position.count >= 2 else {
                    print("❌ '\(entity.originalText)' has malformed position: \(position)")
                    invalidPositions += 1
                    continue
                }
                let start = position[0]
                let end = position[1]

                if start < 0 || end > nsText.length || start >= end {
                    print("❌ '\(entity.originalText)' position [\(start),\(end)] out of bounds (nsText.length=\(nsText.length))")
                    invalidPositions += 1
                } else {
                    let extracted = nsText.substring(with: NSRange(location: start, length: end - start))
                    print("✅ '\(entity.originalText)' [\(start),\(end)] → '\(extracted)' (code: \(entity.replacementCode))")
                }
            }
        }

        XCTAssertGreaterThan(totalPositions, 0, "Should have at least one position across all entities")
        XCTAssertEqual(invalidPositions, 0, "\(invalidPositions) invalid positions found")
    }
}
