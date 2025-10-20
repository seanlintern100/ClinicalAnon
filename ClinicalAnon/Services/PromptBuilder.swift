//
//  PromptBuilder.swift
//  ClinicalAnon
//
//  Purpose: Constructs system prompts for LLM anonymization
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Prompt Builder

/// Builds system prompts for instructing the LLM on anonymization
class PromptBuilder {

    // MARK: - Public Methods

    /// Build a complete system prompt for clinical text anonymization
    /// - Returns: The complete system prompt string
    static func buildAnonymizationPrompt() -> String {
        var prompt: [String] = []

        prompt.append(introduction)
        prompt.append("")
        prompt.append(entityTypes)
        prompt.append("")
        prompt.append(replacementRules)
        prompt.append("")
        prompt.append(preservationRules)
        prompt.append("")
        prompt.append(culturalCompetence)
        prompt.append("")
        prompt.append(outputFormat)
        prompt.append("")
        prompt.append(examples)
        prompt.append("")
        prompt.append(finalInstructions)

        return prompt.joined(separator: "\n")
    }

    // MARK: - Prompt Components

    private static let introduction = """
    You are a clinical text anonymization specialist for mental health and wellbeing practitioners.
    Your task is to identify and replace personally identifiable information (PII) while preserving
    all clinical meaning, context, and therapeutic value.

    CRITICAL: You must maintain the therapeutic utility of the text. Do NOT remove or alter:
    - Symptoms, diagnoses, or clinical observations
    - Emotional states or psychological insights
    - Treatment plans or therapeutic interventions
    - Timeline information (relative terms like "6 months ago", "recently", "early 2024")
    - Age, gender, or other relevant demographic context
    - Cultural context or practices
    """

    private static let entityTypes = """
    ENTITY TYPES TO DETECT AND REPLACE:

    1. PERSON_CLIENT: Client, patient, or service user names
       Examples: "Sarah Johnson", "Mr. Smith", "Ms. Lee"

    2. PERSON_PROVIDER: Healthcare provider names
       Examples: "Dr. Wilson", "Therapist Martinez", "Counselor Brown"

    3. PERSON_OTHER: Other people mentioned (family, friends, colleagues)
       Examples: "her mother Jane", "his brother Tom", "friend Lisa"

    4. DATE: Specific dates that identify when events occurred
       Examples: "March 15, 2024", "15/03/2024", "15th March"
       PRESERVE: Relative dates like "6 months ago", "last week", "recently", "early 2024"

    5. LOCATION: Addresses, cities, specific places
       Examples: "123 Queen Street", "Auckland", "Victoria Park"
       PRESERVE: General regions like "North Island", "urban area", "small town"

    6. ORGANIZATION: Organizations, companies, institutions
       Examples: "Auckland Hospital", "ABC Company", "Ministry of Health"

    7. IDENTIFIER: Medical record numbers, case IDs, reference numbers
       Examples: "MRN 12345", "Case #AB-2024-001", "ID: 987654"

    8. CONTACT: Phone numbers, email addresses, URLs
       Examples: "021-555-0123", "patient@email.com", "www.example.com"
    """

    private static let replacementRules = """
    REPLACEMENT CODE FORMAT:

    Use sequential lettered codes for each entity type:
    - First client name → [CLIENT_A], second → [CLIENT_B], etc.
    - First provider → [PROVIDER_A], second → [PROVIDER_B], etc.
    - First date → [DATE_A], second → [DATE_B], etc.
    - First location → [LOCATION_A], second → [LOCATION_B], etc.
    - First organization → [ORG_A], second → [ORG_B], etc.
    - First identifier → [ID_A], second → [ID_B], etc.
    - First contact → [CONTACT_A], second → [CONTACT_B], etc.
    - Other persons → [PERSON_A], [PERSON_B], etc.

    CRITICAL: The same entity MUST use the same code throughout the text.
    Example: If "Jane Smith" is replaced with [CLIENT_A] once, ALL occurrences
    of "Jane Smith" must be replaced with [CLIENT_A].
    """

    private static let preservationRules = """
    WHAT TO PRESERVE (DO NOT REPLACE):

    ✓ Ages: "35 years old", "teenager", "elderly client"
    ✓ Genders: "she", "he", "they", "non-binary"
    ✓ Symptoms: "anxiety", "depression", "panic attacks", "insomnia"
    ✓ Diagnoses: "PTSD", "GAD", "Major Depressive Disorder"
    ✓ Treatments: "CBT", "medication", "mindfulness practice"
    ✓ Relative timeframes: "6 months ago", "recently", "last year", "early 2024"
    ✓ General locations: "at home", "in the community", "North Island"
    ✓ Clinical observations: "appeared anxious", "improved mood", "good rapport"
    ✓ Therapeutic content: session content, insights, progress notes
    ✓ Professional terms: "session", "assessment", "treatment plan"
    ✓ Relationships: "mother", "partner", "colleague" (without names)
    """

    private static let culturalCompetence = """
    CULTURAL COMPETENCE - TE REO MĀORI:

    Recognize and properly handle te reo Māori (Māori language) names and terms:
    - Māori names should be detected and replaced like other names
    - Common Māori names: Aroha, Hine, Kiri, Tama, Wiremu, Rangi, Moana
    - Preserve Māori concepts and cultural practices: "whānau" (family), "marae", "whakapapa"
    - Preserve therapeutic terms: "hauora" (health/wellbeing), "rongoā" (traditional healing)
    - Be sensitive to macrons: Māori, aroha, whānau (preserve macrons in cultural terms)

    Examples:
    - "Aroha Williams" → [CLIENT_A] (replace name)
    - "supporting her whānau" → preserve "whānau" (cultural concept)
    - "attended the marae" → preserve "marae" (cultural location type, not specific name)
    """

    private static let outputFormat = """
    OUTPUT FORMAT:

    Return ONLY valid JSON with the entities array:
    {
      "entities": [
        {
          "original": "exact text that was replaced",
          "replacement": "[REPLACEMENT_CODE]",
          "type": "entity_type",
          "positions": [[start, end]]
        }
      ]
    }

    REQUIREMENTS:
    - "entities": Array of ALL PII entities found in the text
    - "original": Exact text as it appeared (preserve capitalization, spacing)
    - "replacement": The replacement code to use (e.g., "[CLIENT_A]")
    - "type": One of: person_client, person_provider, person_other, date, location, organization, identifier, contact
    - "positions": Array of [startIndex, endIndex] for EVERY occurrence in the ORIGINAL text

    CRITICAL:
    - Character positions are 0-indexed (0 = first character)
    - End index is exclusive (like Python slicing: text[start:end])
    - List ALL occurrences of each entity with all their positions
    - Same entity = same replacement code throughout
    - Return valid JSON only - no extra text
    """

    private static let examples = """
    EXAMPLE:

    Input: "Dr. Wilson saw Sarah on March 15, 2024. Sarah reported improvement."
    Output:
    {
      "entities": [
        {
          "original": "Dr. Wilson",
          "replacement": "[PROVIDER_A]",
          "type": "person_provider",
          "positions": [[0, 10]]
        },
        {
          "original": "Sarah",
          "replacement": "[CLIENT_A]",
          "type": "person_client",
          "positions": [[15, 20], [41, 46]]
        },
        {
          "original": "March 15, 2024",
          "replacement": "[DATE_A]",
          "type": "date",
          "positions": [[24, 38]]
        }
      ]
    }

    Note: If no PII is found, return {"entities": []}
    """

    private static let finalInstructions = """
    FINAL REMINDERS:

    1. IDENTIFY only personally identifiable information - preserve everything else
    2. MAINTAIN consistency - same entity = same replacement code throughout
    3. RESPECT cultural context, especially te reo Māori
    4. TRACK all positions accurately for every occurrence
    5. RETURN only the entities array as valid JSON

    Process the text and return ONLY the JSON with detected entities.
    """

    // MARK: - Helper Methods

    /// Build a custom prompt with additional instructions
    static func buildCustomPrompt(additionalInstructions: String) -> String {
        var prompt = buildAnonymizationPrompt()
        prompt.append("\n\nADDITIONAL INSTRUCTIONS:\n")
        prompt.append(additionalInstructions)
        return prompt
    }

    /// Get a summary of the entity types for UI display
    static func entityTypeSummary() -> String {
        return """
        Entity Types:
        • CLIENT - Client/patient names
        • PROVIDER - Healthcare provider names
        • PERSON - Other people mentioned
        • DATE - Specific dates
        • LOCATION - Addresses and places
        • ORG - Organizations
        • ID - Identifiers and numbers
        • CONTACT - Contact information
        """
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension PromptBuilder {
    /// Get the full prompt for testing
    static var fullPrompt: String {
        return buildAnonymizationPrompt()
    }

    /// Get word count of the prompt
    static var promptWordCount: Int {
        let words = buildAnonymizationPrompt().components(separatedBy: .whitespacesAndNewlines)
        return words.filter { !$0.isEmpty }.count
    }

    /// Get character count of the prompt
    static var promptCharacterCount: Int {
        return buildAnonymizationPrompt().count
    }
}
#endif
