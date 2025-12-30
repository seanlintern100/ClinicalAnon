//
//  DocumentType.swift
//  Redactor
//
//  Purpose: Unified model for AI document processing types with slider controls
//  Organization: 3 Big Things
//

import Foundation

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
