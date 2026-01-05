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
            You are a clinical writing assistant. Transform the provided raw notes into clean clinical notes.

            Tone: {formality_text}
            Detail: {detail_text}
            Structure: {structure_text}

            Tasks:
            - Fix grammar, spelling, punctuation
            - Organise content by topic/theme
            - Clarify meaning without changing clinical content
            - End with follow-up actions, clearly noting:
              - Actions for the therapist
              - Actions for the client (if any)

            Do NOT add information not present in the original.
            Placeholders like [PERSON_A], [DATE_A] must be preserved exactly.
            Respond with only the clinical notes.
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

            Present the review as structured content ready for clinical review. Use clear headings and consistent formatting.
            """,
        icon: "doc.badge.gearshape",
        isBuiltIn: true,
        defaultSliders: SliderSettings(formality: 4, detail: 4, structure: 4),
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
        .accBSSReview,
        .custom
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
