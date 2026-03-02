//
//  RestoreFlowTests.swift
//  RedactorTests
//
//  Purpose: Integration tests for the Phase 1 → Phase 3 restore flow
//  Verifies that ALL redacted placeholders get restored back to original text
//

import XCTest
@testable import Redactor

@MainActor
final class RestoreFlowTests: XCTestCase {

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

    // MARK: - Full Restore Flow Tests

    /// After redaction, ALL placeholders must have non-empty restore mappings
    func testAllPlaceholdersHaveRestoreMappings() async throws {
        state.inputText = """
        Hamish
        Court coming up
        In and off sych help – some is useful
        ]Stacey Graham- coubsellor/psych – learn ts soe awesomes stuff
        Getting better at life

        Thing Stacey taught me is what to do when I start to feel ngry

        Sister was looking after son but son has moved to akl now.
        1 long term rlation ship for 4 years

        Taking deepbfreaths an help

        Wendy – take sto appoitnmets
        """

        await state.analyze()

        let redactedText = state.displayedRedactedText

        // Find all placeholders in redacted text
        let placeholders = findPlaceholders(in: redactedText)
        XCTAssertFalse(placeholders.isEmpty, "Redacted text should contain placeholders")

        print("📋 Found \(placeholders.count) placeholders in redacted text:")

        // Check each placeholder has a mapping
        let allMappings = engine.entityMapping.allMappings
        let mappingByCode = Dictionary(allMappings.map { ($0.replacement, $0.original) }, uniquingKeysWith: { first, _ in first })

        var missingMappings: [String] = []
        var emptyMappings: [String] = []

        for placeholder in placeholders {
            if let original = mappingByCode[placeholder] {
                if original.isEmpty {
                    emptyMappings.append(placeholder)
                    print("  ⚠️ \(placeholder) → EMPTY original")
                } else {
                    print("  ✅ \(placeholder) → '\(original)'")
                }
            } else {
                missingMappings.append(placeholder)
                print("  ❌ \(placeholder) → NO MAPPING")
            }
        }

        XCTAssertEqual(missingMappings.count, 0,
            "Missing mappings for: \(missingMappings.joined(separator: ", "))")
        XCTAssertEqual(emptyMappings.count, 0,
            "Empty mappings for: \(emptyMappings.joined(separator: ", "))")
    }

    /// Restore must replace ALL placeholders — none should remain in output
    func testRestoreReplacesAllPlaceholders() async throws {
        state.inputText = """
        Hamish
        Court coming up
        In and off sych help – some is useful
        ]Stacey Graham- coubsellor/psych – learn ts soe awesomes stuff
        Getting better at life

        Thing Stacey taught me is what to do when I start to feel ngry

        Sister was looking after son but son has moved to akl now.
        1 long term rlation ship for 4 years

        Taking deepbfreaths an help

        Wendy – take sto appoitnmets
        """

        await state.analyze()

        let redactedText = state.displayedRedactedText
        let placeholdersBeforeRestore = findPlaceholders(in: redactedText)

        // Simulate restore (same as TextReidentifier.restore)
        let reidentifier = TextReidentifier()
        let restoredText = reidentifier.restore(text: redactedText, using: engine.entityMapping)

        let remainingPlaceholders = findPlaceholders(in: restoredText)

        print("📋 Before restore: \(placeholdersBeforeRestore.count) placeholders")
        print("📋 After restore: \(remainingPlaceholders.count) remaining")

        for remaining in remainingPlaceholders {
            print("  ❌ Not restored: \(remaining)")
        }

        XCTAssertEqual(remainingPlaceholders.count, 0,
            "Unreplaced placeholders: \(remainingPlaceholders.joined(separator: ", "))")
    }

    /// Full clinical note: restore must produce text without any placeholders
    func testFullClinicalNoteRestore() async throws {
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

        let redactedText = state.displayedRedactedText
        let placeholders = findPlaceholders(in: redactedText)
        print("📋 \(placeholders.count) placeholders in redacted text")
        print("📝 Redacted text (last 300 chars): '\(String(redactedText.suffix(300)))'")

        // Restore
        let reidentifier = TextReidentifier()
        let restoredText = reidentifier.restore(text: redactedText, using: engine.entityMapping)

        let remaining = findPlaceholders(in: restoredText)
        print("\n📋 \(remaining.count) remaining after restore:")
        for r in remaining {
            print("  ❌ \(r)")
        }

        // Dump all mappings for debugging
        let allMappings = engine.entityMapping.allMappings
        print("\n📋 All \(allMappings.count) mappings:")
        for m in allMappings.sorted(by: { $0.replacement < $1.replacement }) {
            print("  \(m.replacement) → '\(m.original)'")
        }

        XCTAssertEqual(remaining.count, 0,
            "\(remaining.count) placeholders not restored: \(remaining.joined(separator: ", "))")
    }

    /// Test restore with \r\n line endings
    func testRestoreWithCRLFLineEndings() async throws {
        state.inputText = "Hamish\r\nCourt coming up\r\n\r\nStacey Graham- counsellor\r\n\r\nWendy – take to appointments\r\n"

        await state.analyze()

        let redactedText = state.displayedRedactedText
        let reidentifier = TextReidentifier()
        let restoredText = reidentifier.restore(text: redactedText, using: engine.entityMapping)

        let remaining = findPlaceholders(in: restoredText)
        XCTAssertEqual(remaining.count, 0,
            "Unreplaced with \\r\\n: \(remaining.joined(separator: ", "))")
    }

    /// Dump entity mapping state after analysis for debugging
    func testDumpEntityMappingState() async throws {
        state.inputText = """
        Hamish
        Court coming up
        ]Stacey Graham- coubsellor/psych

        Thing Stacey taught me

        Wendy – take sto appoitnmets
        """

        await state.analyze()

        // Print all active entities with their codes
        print("\n🔍 Active entities after analyze:")
        for entity in state.activeEntities {
            print("  Entity: '\(entity.originalText)' → \(entity.replacementCode) (type: \(entity.type), positions: \(entity.positions.count))")
        }

        // Print all mappings
        let allMappings = engine.entityMapping.allMappings
        print("\n🔍 allMappings (\(allMappings.count) entries):")
        for m in allMappings.sorted(by: { $0.replacement < $1.replacement }) {
            print("  \(m.replacement) → '\(m.original)' \(m.original.isEmpty ? "⚠️ EMPTY" : "")")
        }

        // Print redacted text
        let redacted = state.displayedRedactedText
        print("\n🔍 Redacted text:")
        print(redacted)

        // Restore and show result
        let reidentifier = TextReidentifier()
        let restored = reidentifier.restore(text: redacted, using: engine.entityMapping)
        print("\n🔍 Restored text:")
        print(restored)

        // Find mismatches
        let placeholders = findPlaceholders(in: redacted)
        let remaining = findPlaceholders(in: restored)
        if !remaining.isEmpty {
            print("\n❌ MISSING RESTORES:")
            for r in remaining {
                let mapping = allMappings.first { $0.replacement == r }
                if let m = mapping {
                    print("  \(r) → original='\(m.original)' (empty=\(m.original.isEmpty))")
                } else {
                    print("  \(r) → NO MAPPING EXISTS")
                }
            }
        }

        XCTAssertEqual(remaining.count, 0, "\(remaining.count) placeholders not restored")
    }

    /// CLIENT_A single name: [CLIENT_A_FIRST] must restore even when only [CLIENT_A] was redacted
    func testClientVariantCodesRestore() async throws {
        // Manually register a CLIENT entity (single name, no RedactedPerson)
        _ = engine.entityMapping.getReplacementCode(for: "Hamish", type: .personClient)

        // Verify what allMappings generates
        let allMappings = engine.entityMapping.allMappings
        let mappingByCode = Dictionary(
            allMappings.map { ($0.replacement, $0.original) },
            uniquingKeysWith: { first, _ in first }
        )

        print("📋 All mappings for CLIENT entity 'Hamish':")
        for m in allMappings.sorted(by: { $0.replacement < $1.replacement }) {
            print("  \(m.replacement) → '\(m.original)'")
        }

        // The AI uses [CLIENT_A_FIRST] — this MUST have a mapping
        let criticalCodes = ["[CLIENT_A]", "[CLIENT_A_FIRST]", "[CLIENT_A_FULL]", "[CLIENT_A_LAST]", "[CLIENT_A_FIRST_LAST]"]
        for code in criticalCodes {
            XCTAssertNotNil(mappingByCode[code],
                "\(code) must have a mapping — got nil. Available: \(mappingByCode.keys.sorted())")
            if let orig = mappingByCode[code] {
                XCTAssertFalse(orig.isEmpty, "\(code) must have non-empty original")
                print("  ✅ \(code) → '\(orig)'")
            }
        }

        // Test actual restore with AI-style text using CLIENT_A_FIRST
        let aiText = "[CLIENT_A_FIRST] attended the session today. We discussed [CLIENT_A_FIRST]'s goals."
        let reidentifier = TextReidentifier()
        let restored = reidentifier.restore(text: aiText, using: engine.entityMapping)

        XCTAssertFalse(restored.contains("[CLIENT_A"),
            "Restored text should not contain CLIENT placeholders — got: '\(restored)'")
        XCTAssertTrue(restored.contains("Hamish"),
            "Restored text should contain 'Hamish' — got: '\(restored)'")
    }

    /// ROOT CAUSE: detectAIGeneratedPlaceholders adds empty mapping that shadows variant
    func testAIGeneratedPlaceholderDoesNotShadowVariant() async throws {
        // Step 1: Register a CLIENT entity (single name)
        _ = engine.entityMapping.getReplacementCode(for: "Hamish", type: .personClient)

        // Step 2: Simulate detectAIGeneratedPlaceholders finding [CLIENT_A_FIRST]
        // This is what the app does when AI output contains [CLIENT_A_FIRST]
        engine.entityMapping.addAIGeneratedPlaceholder("[CLIENT_A_FIRST]")

        // Step 3: Check allMappings — [CLIENT_A_FIRST] must still have non-empty original
        let allMappings = engine.entityMapping.allMappings
        let mappingByCode = Dictionary(
            allMappings.map { ($0.replacement, $0.original) },
            uniquingKeysWith: { first, _ in first }
        )

        print("📋 After addAIGeneratedPlaceholder('[CLIENT_A_FIRST]'):")
        for m in allMappings.sorted(by: { $0.replacement < $1.replacement }) {
            let marker = m.original.isEmpty ? "❌ EMPTY" : "✅"
            print("  \(marker) \(m.replacement) → '\(m.original)'")
        }

        let firstOrig = mappingByCode["[CLIENT_A_FIRST]"]
        XCTAssertNotNil(firstOrig, "[CLIENT_A_FIRST] must have a mapping")
        XCTAssertFalse(firstOrig?.isEmpty ?? true,
            "[CLIENT_A_FIRST] must NOT have empty original after addAIGeneratedPlaceholder — this is the shadow bug")

        // Verify restore works
        let aiText = "[CLIENT_A_FIRST] attended the session."
        let reidentifier = TextReidentifier()
        let restored = reidentifier.restore(text: aiText, using: engine.entityMapping)
        XCTAssertTrue(restored.contains("Hamish"),
            "Should restore to 'Hamish' — got: '\(restored)'")
    }

    /// Non-person codes: AI-generated [LOCATION_A] must not shadow the real mapping
    func testLocationNotShadowedByAIPlaceholder() async throws {
        // Register a location entity
        _ = engine.entityMapping.getReplacementCode(for: "Taupo", type: .location)

        // Simulate detectAIGeneratedPlaceholders finding [LOCATION_A] in AI output
        engine.entityMapping.addAIGeneratedPlaceholder("[LOCATION_A]")

        let allMappings = engine.entityMapping.allMappings
        let mappingByCode = Dictionary(
            allMappings.map { ($0.replacement, $0.original) },
            uniquingKeysWith: { first, _ in first }
        )

        let orig = mappingByCode["[LOCATION_A]"]
        XCTAssertNotNil(orig, "[LOCATION_A] must have a mapping")
        XCTAssertEqual(orig, "Taupo",
            "[LOCATION_A] must map to 'Taupo', not empty — got: '\(orig ?? "nil")'")

        let aiText = "Client was seen at [LOCATION_A]."
        let reidentifier = TextReidentifier()
        let restored = reidentifier.restore(text: aiText, using: engine.entityMapping)
        XCTAssertTrue(restored.contains("Taupo"), "Should restore to 'Taupo' — got: '\(restored)'")
    }

    /// PERSON single name: [PERSON_A_FIRST] must restore even when only [PERSON_A] was redacted
    func testPersonVariantCodesRestore() async throws {
        _ = engine.entityMapping.getReplacementCode(for: "Wendy", type: .personOther)

        let allMappings = engine.entityMapping.allMappings
        let mappingByCode = Dictionary(
            allMappings.map { ($0.replacement, $0.original) },
            uniquingKeysWith: { first, _ in first }
        )

        let criticalCodes = ["[PERSON_A]", "[PERSON_A_FIRST]", "[PERSON_A_FULL]"]
        for code in criticalCodes {
            XCTAssertNotNil(mappingByCode[code],
                "\(code) must have a mapping")
            if let orig = mappingByCode[code] {
                XCTAssertFalse(orig.isEmpty, "\(code) must have non-empty original")
            }
        }

        let aiText = "[PERSON_A_FIRST] is the support worker."
        let reidentifier = TextReidentifier()
        let restored = reidentifier.restore(text: aiText, using: engine.entityMapping)

        XCTAssertFalse(restored.contains("[PERSON_A"),
            "Should not contain PERSON placeholder — got: '\(restored)'")
        XCTAssertTrue(restored.contains("Wendy"),
            "Should contain 'Wendy' — got: '\(restored)'")
    }

    /// Simulate AI output: same codes in rewritten text must all restore
    func testRestoreFromSimulatedAIOutput() async throws {
        state.inputText = """
        Hamish
        Court coming up
        In and off sych help – some is useful
        ]Stacey Graham- coubsellor/psych – learn ts soe awesomes stuff
        Getting better at life

        Thing Stacey taught me is what to do when I start to feel ngry

        Sister was looking after son but son has moved to akl now.
        1 long term rlation ship for 4 years

        Taking deepbfreaths an help

        Wendy – take sto appoitnmets
        """

        await state.analyze()

        let redactedText = state.displayedRedactedText
        let placeholders = findPlaceholders(in: redactedText)

        print("📋 Phase 1 redacted text has \(placeholders.count) unique placeholders:")
        for p in placeholders {
            print("  \(p)")
        }

        // Simulate AI rewriting: replace surrounding text but keep codes unchanged
        var aiOutput = redactedText
        aiOutput = aiOutput.replacingOccurrences(of: "Court coming up", with: "Has an upcoming court appearance")
        aiOutput = aiOutput.replacingOccurrences(of: "Getting better at life", with: "Reports improvement in overall wellbeing")

        let aiPlaceholders = findPlaceholders(in: aiOutput)
        print("\n📋 AI output has \(aiPlaceholders.count) unique placeholders")

        // Restore from AI output
        let reidentifier = TextReidentifier()
        let restoredText = reidentifier.restore(text: aiOutput, using: engine.entityMapping)

        let remaining = findPlaceholders(in: restoredText)

        // Log all mappings and their presence in text
        let allMappings = engine.entityMapping.allMappings
        let mappingByCode = Dictionary(
            allMappings.map { ($0.replacement, $0.original) },
            uniquingKeysWith: { first, _ in first }
        )

        print("\n📋 Mapping coverage for AI output placeholders:")
        for p in aiPlaceholders {
            if let orig = mappingByCode[p] {
                let inResult = !restoredText.contains(p)
                print("  \(inResult ? "✅" : "❌") \(p) → '\(orig)' (restored: \(inResult))")
            } else {
                print("  ❌ \(p) → NO MAPPING")
            }
        }

        XCTAssertEqual(remaining.count, 0,
            "\(remaining.count) placeholders not restored from AI output: \(remaining.joined(separator: ", "))")
    }

    /// Test that ALL variant codes for single-name people have fallback mappings
    func testSingleNameVariantFallback() async throws {
        state.inputText = """
        Hamish came in today.
        We discussed his goals.

        Wendy – take to appointments
        """

        await state.analyze()

        let allMappings = engine.entityMapping.allMappings
        let mappingByCode = Dictionary(
            allMappings.map { ($0.replacement, $0.original) },
            uniquingKeysWith: { first, _ in first }
        )

        // Find all person base IDs
        let personCodes = allMappings.filter { $0.replacement.contains("PERSON") || $0.replacement.contains("CLIENT") }
        let baseIds = Set(personCodes.compactMap { code -> String? in
            let stripped = code.replacement.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            // Find base: take everything up to and including the letter after last TYPE_
            let parts = stripped.split(separator: "_")
            guard parts.count >= 2 else { return nil }
            // Base is TYPE_LETTER (first two parts)
            return "\(parts[0])_\(parts[1])"
        })

        print("📋 Person base IDs: \(baseIds.sorted())")

        // Check ALL variant codes exist for each base
        let variants = ["", "_FULL", "_FIRST", "_LAST", "_MIDDLE", "_FIRST_LAST", "_FIRST_MID", "_FORMAL"]
        var missingVariants: [String] = []

        for baseId in baseIds.sorted() {
            for variant in variants {
                let code = "[\(baseId)\(variant)]"
                if let orig = mappingByCode[code] {
                    let isEmpty = orig.isEmpty
                    print("  \(isEmpty ? "⚠️" : "✅") \(code) → '\(orig)'")
                    if isEmpty {
                        missingVariants.append(code)
                    }
                } else {
                    print("  ❌ \(code) → NOT IN MAPPINGS")
                    missingVariants.append(code)
                }
            }
        }

        XCTAssertEqual(missingVariants.count, 0,
            "Missing/empty variant mappings: \(missingVariants.joined(separator: ", "))")
    }

    /// Test that variant codes used in AI output are properly restored
    func testVariantCodeRestore() async throws {
        state.inputText = """
        Hamish came in today.
        Stacey Graham is the counsellor.

        Wendy – take to appointments
        """

        await state.analyze()

        let allMappings = engine.entityMapping.allMappings
        let mappingByCode = Dictionary(
            allMappings.map { ($0.replacement, $0.original) },
            uniquingKeysWith: { first, _ in first }
        )

        // Build AI output using variant codes for each person base code
        var aiText = ""
        for m in allMappings {
            let code = m.replacement
            guard code.contains("PERSON") || code.contains("CLIENT") else { continue }

            // Only process base codes (TYPE_LETTER, exactly 2 parts when split)
            let inner = code.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let parts = inner.split(separator: "_")
            guard parts.count == 2 else { continue }

            let baseId = inner
            aiText += "The client \(code) attended today.\n"
            aiText += "[\(baseId)_FIRST] discussed their goals.\n"
            aiText += "[\(baseId)_LAST] was noted in records.\n"
            aiText += "Referred to as [\(baseId)_FULL] in records.\n\n"
        }

        guard !aiText.isEmpty else {
            print("⚠️ No person codes found, skipping variant test")
            return
        }

        print("📋 AI text with variants:\n\(aiText)")

        let reidentifier = TextReidentifier()
        let restoredText = reidentifier.restore(text: aiText, using: engine.entityMapping)

        let remaining = findPlaceholders(in: restoredText)
        print("\n📋 After restore: \(remaining.count) remaining")
        for r in remaining {
            let hasMapping = mappingByCode[r] != nil
            let origText = mappingByCode[r] ?? "NO MAPPING"
            print("  ❌ \(r) → '\(origText)' (in mappings: \(hasMapping))")
        }

        XCTAssertEqual(remaining.count, 0,
            "Variant codes not restored: \(remaining.joined(separator: ", "))")
    }

    // MARK: - Reclassification Tests

    /// After reclassifying PERSON → CLIENT, EntityMapping must update so
    /// variant codes like [CLIENT_A_FIRST] restore correctly
    func testReclassificationUpdatesMappings() async throws {
        state.inputText = """
        Hamish came in today.
        Stacey Graham is the counsellor.
        Wendy – take to appointments
        """

        await state.analyze()

        // Find all PERSON entities
        let personEntities = state.activeEntities.filter { $0.type == .personOther }
        XCTAssertFalse(personEntities.isEmpty, "Should have PERSON entities before reclassify")

        // Find an anchor PERSON entity to reclassify
        guard let anchor = personEntities.first(where: { $0.isAnchor }) ?? personEntities.first else {
            XCTFail("No PERSON entity found to reclassify")
            return
        }

        let oldCode = anchor.replacementCode
        let originalText = anchor.originalText
        print("📋 Reclassifying: '\(originalText)' (\(oldCode)) from PERSON → CLIENT")

        // Verify old mapping exists
        let oldMappings = engine.entityMapping.allMappings
        let hadOldCode = oldMappings.contains { $0.replacement == oldCode }
        XCTAssertTrue(hadOldCode, "Old code \(oldCode) should exist in mappings before reclassify")

        // Reclassify to CLIENT
        state.reclassifyEntity(anchor.id, to: .personClient)

        // The entity should now have a CLIENT code
        let reclassifiedEntity = state.activeEntities.first { $0.originalText == originalText }
        XCTAssertNotNil(reclassifiedEntity, "Entity should still exist after reclassify")
        XCTAssertTrue(reclassifiedEntity!.replacementCode.contains("CLIENT"),
            "Reclassified entity should have CLIENT prefix, got: \(reclassifiedEntity!.replacementCode)")

        let newCode = reclassifiedEntity!.replacementCode
        print("📋 New code: \(newCode)")

        // Verify EntityMapping was updated
        let newMappings = engine.entityMapping.allMappings
        let hasNewCode = newMappings.contains { $0.replacement == newCode }
        XCTAssertTrue(hasNewCode,
            "New code \(newCode) must exist in EntityMapping after reclassify")

        // Verify variant codes exist for the new CLIENT code
        let newBaseInner = newCode.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let parts = newBaseInner.split(separator: "_")
        let baseId = parts.count >= 2 ? "\(parts[0])_\(parts[1])" : newBaseInner

        let variantSuffixes = ["_FIRST", "_LAST", "_FULL"]
        let mappingByCode = Dictionary(
            newMappings.map { ($0.replacement, $0.original) },
            uniquingKeysWith: { first, _ in first }
        )

        for suffix in variantSuffixes {
            let variantCode = "[\(baseId)\(suffix)]"
            let orig = mappingByCode[variantCode]
            print("  \(orig != nil && !orig!.isEmpty ? "✅" : "❌") \(variantCode) → '\(orig ?? "MISSING")'")
            XCTAssertNotNil(orig, "Variant \(variantCode) must exist in mappings after reclassify")
            if let orig = orig {
                XCTAssertFalse(orig.isEmpty, "Variant \(variantCode) must have non-empty original")
            }
        }

        // Now test restore with AI-style variant codes
        let aiText = "\(newCode) attended today. [\(baseId)_FIRST] discussed progress."
        let reidentifier = TextReidentifier()
        let restored = reidentifier.restore(text: aiText, using: engine.entityMapping)

        let remaining = findPlaceholders(in: restored)
        print("📋 Restored: '\(restored)'")
        XCTAssertEqual(remaining.count, 0,
            "All CLIENT variant codes should restore. Remaining: \(remaining.joined(separator: ", "))")
    }

    /// EntityMapping.updateBaseId correctly moves mappings and RedactedPersons
    func testUpdateBaseIdDirectly() {
        let mapping = EntityMapping()

        // Set up a PERSON_A mapping with a RedactedPerson
        let _ = mapping.getVariantReplacementCode(for: "John Smith", type: .personOther)

        // Verify PERSON_A exists
        let before = mapping.allMappings
        let hasPersonA = before.contains { $0.replacement == "[PERSON_A]" || $0.replacement.hasPrefix("[PERSON_A_") }
        XCTAssertTrue(hasPersonA, "Should have PERSON_A mappings before updateBaseId")
        XCTAssertNotNil(mapping.redactedPersons["PERSON_A"], "Should have RedactedPerson for PERSON_A")

        // Reclassify to CLIENT_A
        mapping.updateBaseId(from: "PERSON_A", to: "CLIENT_A")

        // Verify CLIENT_A exists and PERSON_A is gone
        let after = mapping.allMappings
        let hasClientA = after.contains { $0.replacement == "[CLIENT_A]" || $0.replacement.hasPrefix("[CLIENT_A_") }
        let stillHasPersonA = after.contains { $0.replacement == "[PERSON_A]" || $0.replacement.hasPrefix("[PERSON_A_") }

        XCTAssertTrue(hasClientA, "Should have CLIENT_A mappings after updateBaseId")
        XCTAssertFalse(stillHasPersonA, "Should NOT have PERSON_A mappings after updateBaseId")
        XCTAssertNil(mapping.redactedPersons["PERSON_A"], "PERSON_A RedactedPerson should be removed")
        XCTAssertNotNil(mapping.redactedPersons["CLIENT_A"], "CLIENT_A RedactedPerson should exist")

        // Verify variant codes resolve
        let mappingByCode = Dictionary(
            after.map { ($0.replacement, $0.original) },
            uniquingKeysWith: { first, _ in first }
        )

        XCTAssertEqual(mappingByCode["[CLIENT_A_FIRST]"], "John",
            "CLIENT_A_FIRST should map to 'John'")
        XCTAssertEqual(mappingByCode["[CLIENT_A_LAST]"], "Smith",
            "CLIENT_A_LAST should map to 'Smith'")
    }

    /// syncMapping fixes stale codes: mapping has [PERSON_A] but entity says [CLIENT_A]
    func testSyncMappingFixesStaleCodes() {
        let mapping = EntityMapping()

        // Simulate initial analysis: "Hamish" mapped as PERSON_A
        mapping.addMapping(originalText: "Hamish", replacementCode: "[PERSON_A]")

        // Verify stale state
        XCTAssertEqual(mapping.existingMapping(for: "Hamish"), "[PERSON_A]")

        // Simulate source document entity with reclassified code
        mapping.syncMapping(originalText: "Hamish", replacementCode: "[CLIENT_A]")

        // Mapping should now be CLIENT_A
        XCTAssertEqual(mapping.existingMapping(for: "Hamish"), "[CLIENT_A]",
            "syncMapping should update stale PERSON_A → CLIENT_A")

        // Verify variant codes exist
        let allMappings = mapping.allMappings
        let mappingByCode = Dictionary(
            allMappings.map { ($0.replacement, $0.original) },
            uniquingKeysWith: { first, _ in first }
        )

        XCTAssertEqual(mappingByCode["[CLIENT_A]"], "Hamish",
            "CLIENT_A should map to 'Hamish'")
        XCTAssertEqual(mappingByCode["[CLIENT_A_FIRST]"], "Hamish",
            "CLIENT_A_FIRST should map to 'Hamish'")
        XCTAssertNil(mappingByCode["[PERSON_A]"],
            "PERSON_A should be gone after sync")

        // Restore should work
        let reidentifier = TextReidentifier()
        let aiText = "[CLIENT_A_FIRST] attended today. [CLIENT_A] was assessed."
        let restored = reidentifier.restore(text: aiText, using: mapping)

        XCTAssertFalse(restored.contains("[CLIENT_A"),
            "All CLIENT_A codes should be restored — got: '\(restored)'")
        XCTAssertTrue(restored.contains("Hamish"),
            "Restored text should contain 'Hamish' — got: '\(restored)'")
    }

    /// syncMapping with RedactedPerson migrates person data
    func testSyncMappingMigratesRedactedPerson() {
        let mapping = EntityMapping()

        // Create a multi-word person as PERSON_A (creates RedactedPerson)
        let _ = mapping.getVariantReplacementCode(for: "John Smith", type: .personOther)
        XCTAssertNotNil(mapping.redactedPersons["PERSON_A"])

        // Sync with reclassified code
        mapping.syncMapping(originalText: "John Smith", replacementCode: "[CLIENT_A]")

        // RedactedPerson should be migrated
        XCTAssertNil(mapping.redactedPersons["PERSON_A"],
            "PERSON_A RedactedPerson should be removed")
        XCTAssertNotNil(mapping.redactedPersons["CLIENT_A"],
            "CLIENT_A RedactedPerson should exist")

        // All CLIENT variants should have correct name components
        let allMappings = mapping.allMappings
        let mappingByCode = Dictionary(
            allMappings.map { ($0.replacement, $0.original) },
            uniquingKeysWith: { first, _ in first }
        )

        XCTAssertEqual(mappingByCode["[CLIENT_A_FIRST]"], "John")
        XCTAssertEqual(mappingByCode["[CLIENT_A_LAST]"], "Smith")
    }

    // MARK: - Helpers

    /// Find all bracket-enclosed placeholders in text
    private func findPlaceholders(in text: String) -> [String] {
        let pattern = "\\[[A-Z]+_[A-Z0-9]+(?:_[A-Z]+)*\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var seen = Set<String>()
        var result: [String] = []
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let placeholder = String(text[matchRange])
            if seen.insert(placeholder).inserted {
                result.append(placeholder)
            }
        }
        return result
    }
}
