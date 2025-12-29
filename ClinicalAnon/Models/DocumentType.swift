//
//  DocumentType.swift
//  Redactor
//
//  Purpose: Unified model for AI document processing types
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Document Type

struct DocumentType: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var prompt: String
    var icon: String
    var isBuiltIn: Bool

    // MARK: - Built-in Types

    static let polish = DocumentType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Polish",
        prompt: """
            You are a clinical writing assistant. POLISH the provided clinical notes:
            - Fix grammar, spelling, and punctuation errors
            - Improve clarity and readability
            - Maintain professional clinical tone
            - Preserve all medical information accurately
            - Do NOT add or remove clinical details

            The text contains placeholders like [PERSON_A], [DATE_A] - keep them exactly as they appear.
            Respond with ONLY the polished text.
            """,
        icon: "sparkles",
        isBuiltIn: true
    )

    static let progressNote = DocumentType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Progress Note",
        prompt: """
            You are a clinical writing assistant. Generate a PROGRESS NOTE with:
            - Client/Patient identification (using placeholders)
            - Date of session
            - Attendees
            - Presenting issues/concerns
            - Session content/interventions
            - Client response/observations
            - Plan/next steps

            Preserve placeholders like [PERSON_A], [DATE_A] exactly.
            Use ONLY information provided. Respond with the document only.
            """,
        icon: "doc.text",
        isBuiltIn: true
    )

    static let assessment = DocumentType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Assessment",
        prompt: """
            You are a clinical writing assistant. Generate an ASSESSMENT with:
            - Identifying information
            - Referral source and reason
            - Presenting problems
            - Relevant history
            - Mental status/observations
            - Assessment findings
            - Formulation/diagnosis considerations
            - Recommendations

            Preserve placeholders exactly. Use ONLY information provided.
            """,
        icon: "clipboard",
        isBuiltIn: true
    )

    static let report = DocumentType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Report",
        prompt: """
            You are a clinical writing assistant. Generate a comprehensive REPORT including:
            - Client identification
            - Referral information
            - Personal/family background
            - Developmental history
            - Education and employment
            - Current living situation
            - Presenting issues and challenges
            - Mental health history
            - Substance use (alcohol, drugs)
            - Risk assessment
            - Clinical formulation
            - Recommendations and plan

            Preserve placeholders exactly. Use ONLY information provided.
            """,
        icon: "doc.richtext",
        isBuiltIn: true
    )

    static let dischargeSummary = DocumentType(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        name: "Discharge Summary",
        prompt: """
            You are a clinical writing assistant. Generate a DISCHARGE SUMMARY with:
            - Client/Patient identification
            - Dates of service
            - Reason for admission/referral
            - Treatment provided
            - Progress made
            - Current status
            - Follow-up recommendations
            - Discharge plan

            Preserve placeholders exactly. Use ONLY information provided.
            """,
        icon: "arrow.right.doc",
        isBuiltIn: true
    )

    /// All built-in document types in display order
    static let builtInTypes: [DocumentType] = [
        .polish,
        .progressNote,
        .assessment,
        .report,
        .dischargeSummary
    ]

    /// Get the default prompt for a built-in type by ID
    static func defaultPrompt(for id: UUID) -> String? {
        builtInTypes.first { $0.id == id }?.prompt
    }
}
