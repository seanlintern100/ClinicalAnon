//
//  DocumentType.swift
//  Redactor
//
//  Purpose: Unified model for AI document processing types with slider controls
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Text Input Type

/// Classification of input text to help AI understand source material
enum TextInputType: String, CaseIterable, Codable {
    case roughNotes = "Rough clinical notes"
    case completedNotes = "Previous completed clinical notes"
    case otherReports = "Reports by other people"
    case other = "Other"

    var description: String {
        switch self {
        case .roughNotes:
            return "Your own rough notes that need refining"
        case .completedNotes:
            return "Your own previous notes for reference"
        case .otherReports:
            return "Reports or documents written by others"
        case .other:
            return "Other reference materials"
        }
    }

    var icon: String {
        switch self {
        case .roughNotes: return "note.text"
        case .completedNotes: return "doc.text.fill"
        case .otherReports: return "person.2.fill"
        case .other: return "doc.questionmark"
        }
    }
}

// MARK: - Slider Settings

struct SliderSettings: Codable, Equatable {
    var formality: Int = 3  // 1-5
    var detail: Int = 3     // 1-5
    var structure: Int = 3  // 1-5

    // MARK: - Formality Texts

    static let formalityTexts: [String] = [
        "Casual, warm tone suitable for internal notes or client-friendly summaries",
        "Conversational but professional — relaxed clinical language",
        "Standard professional clinical tone",
        "Formal clinical language suitable for external correspondence",
        "Precise, formal language appropriate for medico-legal or funding contexts"
    ]

    // MARK: - Detail Texts

    static let detailTexts: [String] = [
        "Brief — essential points only",
        "Concise — key information with minimal elaboration",
        "Balanced — sufficient detail for clinical clarity",
        "Thorough — comprehensive coverage of relevant information",
        "Exhaustive — preserve all available detail"
    ]

    // MARK: - Structure Texts

    static let structureTexts: [String] = [
        "Flowing narrative — minimal headings",
        "Light structure — occasional groupings",
        "Clear sections — organised by topic",
        "Formal sections — consistent headings throughout",
        "Rigid template — strict section format"
    ]

    // MARK: - Computed Properties

    var formalityText: String {
        Self.formalityTexts[max(0, min(formality - 1, 4))]
    }

    var detailText: String {
        Self.detailTexts[max(0, min(detail - 1, 4))]
    }

    var structureText: String {
        Self.structureTexts[max(0, min(structure - 1, 4))]
    }
}

// MARK: - Document Type

struct DocumentType: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var promptTemplate: String  // Contains {formality_text}, {detail_text}, {structure_text} placeholders
    var icon: String
    var isBuiltIn: Bool
    var isUserCreated: Bool = false  // True for persistent user-created types
    var defaultSliders: SliderSettings
    var customInstructions: String  // For Custom type only

    // MARK: - Prompt Building

    /// Build the final prompt by injecting slider text values
    func buildPrompt(with sliders: SliderSettings) -> String {
        var prompt = promptTemplate
        prompt = prompt.replacingOccurrences(of: "{formality_text}", with: sliders.formalityText)
        prompt = prompt.replacingOccurrences(of: "{detail_text}", with: sliders.detailText)
        prompt = prompt.replacingOccurrences(of: "{structure_text}", with: sliders.structureText)
        prompt = prompt.replacingOccurrences(of: "{user_custom_instructions}", with: customInstructions)
        return prompt
    }

    // MARK: - Template Editing Helpers

    /// The style block that gets injected into templates (controlled by sliders)
    static let styleBlockTemplate = """
        Tone: {formality_text}
        Detail: {detail_text}
        Structure: {structure_text}
        """

    /// Strip the style block from a template for display in editor
    /// Users shouldn't edit these lines as they're controlled by sliders
    static func stripStyleBlock(from template: String) -> String {
        var lines = template.components(separatedBy: "\n")

        // Find and remove the style lines
        lines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("Tone: {formality_text}") &&
                   !trimmed.hasPrefix("Detail: {detail_text}") &&
                   !trimmed.hasPrefix("Structure: {structure_text}")
        }

        // Clean up any resulting double blank lines
        var result: [String] = []
        var lastWasBlank = false
        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank && lastWasBlank {
                continue // Skip consecutive blank lines
            }
            result.append(line)
            lastWasBlank = isBlank
        }

        return result.joined(separator: "\n")
    }

    /// Inject the style block back into a template after editing
    /// Inserts after the first line (the role statement)
    static func injectStyleBlock(into template: String) -> String {
        var lines = template.components(separatedBy: "\n")

        // Find insertion point - after first non-empty line
        var insertIndex = 1
        for (index, line) in lines.enumerated() {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                insertIndex = index + 1
                break
            }
        }

        // Insert blank line, style block, blank line
        let styleLines = [
            "",
            "Tone: {formality_text}",
            "Detail: {detail_text}",
            "Structure: {structure_text}",
            ""
        ]

        lines.insert(contentsOf: styleLines, at: min(insertIndex, lines.count))

        return lines.joined(separator: "\n")
    }

    // MARK: - Built-in Types

    static let notes = DocumentType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Notes",
        promptTemplate: """
            You are a clinical writing assistant helping psychologists transform rough session notes into clean, professional documentation.

            ## Voice
            Write warmly and directly. Be clear without being clinical. Use plain language a colleague would understand—not academic jargon. Think "practical and human" rather than "formal and distant."

            ## Tone Settings
            Formality: {formality_text}
            Detail Level: {detail_text}
            Structure: {structure_text}

            ## Core Tasks
            1. Fix spelling, grammar, and punctuation
            2. Organise content logically (by theme or chronology—preserve whichever structure best reflects the session flow)
            3. Clarify ambiguous phrasing while preserving clinical meaning and intent
            4. Retain the clinician's voice and hedging (e.g., "query sleep difficulties" stays as a query, not a diagnosis)

            ## Strict Boundaries
            - NEVER infer clinical content not explicitly present
            - NEVER change clinical observations, risk assessments, or diagnostic impressions
            - Preserve all placeholders exactly: [DATE_A], [LOCATION_A], etc.
            - If content is unclear or contradictory, flag with [UNCLEAR: original text] rather than guessing

            ## Person References
            - Use [CLIENT_A_FIRST] throughout for the primary client
            - For others: [PERSON_B_FIRST], [PERSON_C_FIRST], etc.

            ## Closing Structure
            End every note with:

            **Follow-up Actions**

            Therapist actions:
            - [List tasks]

            Client actions (if any):
            - [List homework/tasks]

            Next session:
            - [Date/time or "To be scheduled"]

            ## Output Format

            First, output the cleaned clinical notes (this becomes the formal record).

            Then add the marker [REVIEW] on its own line, followed by a brief clinical review covering:
            - Unclear or ambiguous content (what you flagged and why)
            - Risk indicators identified (suicidal ideation, self-harm, safeguarding concerns, etc.)
            - Suggested follow-up actions (assessments, referrals, gaps to clarify)

            Keep the review concise and actionable.
            """,
        icon: "doc.text",
        isBuiltIn: true,
        defaultSliders: SliderSettings(formality: 3, detail: 3, structure: 3),
        customInstructions: ""
    )

    static let report = DocumentType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Report",
        promptTemplate: """
            You are a clinical writing assistant. Generate a clinical report from the provided notes.

            Tone: {formality_text}
            Detail: {detail_text}
            Structure: {structure_text}

            Audience: Case managers, external services, or funding bodies.

            Content guidance:
            - Present the person from a biopsychosocial perspective where relevant
            - Summarise presenting concerns and context
            - Include relevant clinical background and progress
            - Highlight strengths and protective factors
            - Provide practical recommendations the reader can act on
            - Use occasional direct quotes from source documents to illustrate key points
              (e.g., "As noted by [PERSON_B] in their report dated [DATE_C], '[quoted text]'")
            - Reference quotes with the author's name and report date using redacted placeholders
            - If source documents conflict, prefer "User's rough notes" or "User's completed notes"
              over "Report by another person" (the user's notes are likely more current)

            Person references:
            - Introduce people by first and last name once at the start (e.g., "[CLIENT_A_FIRST_LAST]")
            - Use first name only for subsequent references throughout (e.g., "[CLIENT_A_FIRST]")
            - This creates a more natural, less formal tone

            Maintain professional, objective tone appropriate for external readers.
            Placeholders like [PERSON_A], [DATE_A] must be preserved exactly.
            Use only information provided — do not invent details.
            Respond with only the report.
            """,
        icon: "doc.richtext",
        isBuiltIn: true,
        defaultSliders: SliderSettings(formality: 4, detail: 4, structure: 4),
        customInstructions: ""
    )

    static let accBSSReview = DocumentType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "ACC BSS Review",
        promptTemplate: """
            You are a clinical writing assistant.

            Tone: {formality_text}
            Detail: {detail_text}
            Structure: {structure_text}

            Context:
            You are assisting a psychologist in preparing a Behaviour Support Service (BSS) review report for ACC. You will be provided with:
            - The original assessment report containing client context and agreed goals
            - Redacted clinical notes from the review period

            The review report is for a case manager and covers either a 3, 6, or 9 month period.

            Critical Instructions:
            - Preserve all placeholders exactly as written (e.g., [PERSON_A], [DATE_A], [LOCATION_B])
            - Use only information provided — do not invent or infer details
            - Respond with only the requested content — no preamble or commentary
            - Person references: Introduce people by first and last name once (e.g., "[CLIENT_A_FIRST_LAST]"),
              then use first name only for subsequent references (e.g., "[CLIENT_A_FIRST]")

            Your Task:
            Analyse the clinical notes against each goal from the original assessment report. For each goal, generate a summary focused primarily on actions completed and outcomes achieved.

            Output Structure:

            For Each Goal:
            Goal [Number]: [Goal statement from original assessment]

            Actions completed and impact/outcomes:
            Summarise interventions delivered, strategies implemented, and observable or reported changes. Include specific examples from notes where available. Note session frequency and engagement level.

            Amendments (only if clearly indicated):
            Include this section only if the notes explicitly support a recommendation to modify the goal, adjust the service delivery plan, or amend the purchase order. State the proposed change and rationale.

            Additional Section (if applicable):

            Other Significant Outcomes:
            Include only if the notes document notable events not captured under specific goals, such as:
            - Changes in circumstances
            - Critical incidents
            - Engagement with other services
            - Risk-related observations

            Guidance:
            - Prioritise actions and outcomes — This is the primary focus
            - Be factual — Base all statements on documented evidence
            - Preserve redaction placeholders — Do not alter or interpret them
            - Include amendments only when warranted — Do not suggest changes speculatively
            - Note gaps — If information is insufficient to comment on a goal, state this
            - Quantify where possible — Session counts, timeframes, frequency
            - If sources conflict, prefer "User's rough notes" or "User's completed notes"
              over "Report by another person" (the user's notes are likely more current)

            Present the review as structured content ready for clinical review. Use clear headings and consistent formatting.
            """,
        icon: "doc.badge.gearshape",
        isBuiltIn: true,
        defaultSliders: SliderSettings(formality: 4, detail: 4, structure: 4),
        customInstructions: ""
    )

    static let accBSSReport = DocumentType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        name: "ACC BSS Report",
        promptTemplate: """
            You are a clinical writing assistant specialising in psychological assessment and support planning. Synthesise a new clinical report by integrating information from ALL available documents in memory. Do not simply reformat a single source document. Weight sources as follows:
            - Primary: User's clinical notes, rough notes, session notes
            - Secondary: External reports, assessments by other providers

            Where sources conflict, prefer the user's own notes (likely more current).

            Tone: {formality_text}
            Detail: {detail_text}
            Structure: {structure_text}

            Report Focus:
            Psychological and behavioural functioning — not medical management. Explain HOW injury effects, psychological factors, and social stressors interact to produce concerning behaviours.

            Structure:
            1. Introduction: Person, family composition, living situation
            2. Injury history and impact on functioning
            3. Employment history and current situation
            4. Recent legal issues (if applicable)
            5. Background medical issues (brief, relevant only)
            6. Current mental health presentation
            7. Biopsychosocial formulation: Explain current behaviours of concern (e.g., aggression, lack of motivation, inappropriate social behaviour). Identify significant triggers and setting events.
            8. Intervention goals: Three key goals with practical strategies for the support period. Goals should address presenting concerns such as:
               - Behavioural regulation
               - Daily activity / motivation
               - Social functioning

               Strategies should account for any cognitive limitations identified: external structure, prompts, simple concrete steps, immediate reinforcement as needed.

            Tone & Style:
            - Lean toward practical and accessible; minimise repetition and overlap
            - Audience: Case managers and family members

            Content Guidance:
            - Present the person from a biopsychosocial perspective
            - Highlight strengths and protective factors alongside difficulties
            - Provide practical recommendations the reader can act on
            - Use occasional direct quotes from source documents to illustrate key points
              (e.g., "As noted by [PERSON_B] in their assessment dated [DATE_C], '[quoted text]'")
            - If source documents conflict, prefer "User's rough notes" or "User's completed notes" over external reports (user's notes are likely more current)

            Person References:
            Use contextually appropriate name forms:
            - Introduce by full name at first mention (e.g., [CLIENT_A_FIRST_LAST])
            - Use first name for subsequent references (e.g., [CLIENT_A_FIRST])

            Critical Rules:
            - Preserve all placeholders exactly: [PERSON_A], [DATE_A], [ORG_B], etc.
            - Use only information from provided documents — do not invent details
            - If information is missing for a section, note briefly or omit
            - Respond with only the report
            """,
        icon: "brain.head.profile",
        isBuiltIn: true,
        defaultSliders: SliderSettings(formality: 3, detail: 4, structure: 4),
        customInstructions: ""
    )

    static let summarise = DocumentType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        name: "Summary",
        promptTemplate: """
            You are a clinical summarisation assistant. Create a clear, meaningful summary of the provided text.

            Tone: {formality_text}
            Detail: {detail_text}
            Structure: {structure_text}

            Instructions:
            - Identify if the text contains multiple separate documents (e.g., different reports, notes from different dates, assessments)
            - If multiple documents are present, provide a separate summary for each, clearly labelled
            - For each document/section, extract:
              - Key findings and observations
              - Important clinical information
              - Recommendations or actions noted
              - Relevant dates and timeframes
            - Preserve the clinical meaning without adding interpretation
            - Keep summaries concise but comprehensive

            Format:
            - If single document: Provide one cohesive summary
            - If multiple documents: Use clear headings to separate each summary (e.g., "## Assessment Report - [DATE_A]", "## Progress Notes - [DATE_B]")

            Person references:
            - Introduce people by first and last name once at the start (e.g., "[CLIENT_A_FIRST_LAST]")
            - Use first name only for subsequent references throughout (e.g., "[CLIENT_A_FIRST]")
            - This creates a more natural, less formal tone

            Do NOT add information not present in the original.
            Placeholders like [PERSON_A], [DATE_A] must be preserved exactly.
            Respond with only the summary/summaries.
            """,
        icon: "doc.text.magnifyingglass",
        isBuiltIn: true,
        defaultSliders: SliderSettings(formality: 3, detail: 3, structure: 4),
        customInstructions: ""
    )

    static let custom = DocumentType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Custom",
        promptTemplate: """
            You are a clinical writing assistant.

            Tone: {formality_text}
            Detail: {detail_text}
            Structure: {structure_text}

            {user_custom_instructions}

            Placeholders like [PERSON_A], [DATE_A] must be preserved exactly.
            Use only information provided — do not invent details.
            Respond with only the requested content.
            """,
        icon: "square.and.pencil",
        isBuiltIn: true,
        defaultSliders: SliderSettings(formality: 3, detail: 3, structure: 3),
        customInstructions: ""
    )

    /// All built-in document types in display order
    static let builtInTypes: [DocumentType] = [
        .notes,
        .report,
        .summarise,
        .accBSSReport,
        .accBSSReview
    ]

    /// Get the default prompt template for a built-in type by ID
    static func defaultPromptTemplate(for id: UUID) -> String? {
        builtInTypes.first { $0.id == id }?.promptTemplate
    }

    /// Get the default sliders for a built-in type by ID
    static func defaultSliders(for id: UUID) -> SliderSettings? {
        builtInTypes.first { $0.id == id }?.defaultSliders
    }
}
