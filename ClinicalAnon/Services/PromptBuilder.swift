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
    You are a text anonymization specialist. Your ONLY job is to find and replace these 8 types of personally identifiable information (PII).
    """

    private static let entityTypes = """
    FIND AND REPLACE THESE 8 TYPES:

    1. CLIENT_NAME: The client's/patient's name
       Examples: "Emma Rodriguez", "Mr. Chen", "Wiremu"

    2. PROVIDER_NAME: Healthcare provider names
       Examples: "Dr. Anderson", "Counselor White"

    3. OTHER_NAME: Any other person's name
       Examples: "Rachel", "David", "Sofia", "Aroha"
       Each name gets its own replacement, even in lists

    4. SPECIFIC_DATE: Exact dates in any format
       Examples: "June 3, 2023", "03/06/2023", "12/08/2021"

    5. PLACE: Cities, addresses, specific locations
       Examples: "Wellington", "45 High Street", "Mercy Hospital"

    6. ORGANIZATION: Company or organization names
       Examples: "BuildCo Ltd", "Ministry of Health", "CML"

    7. ID_NUMBER: Medical records, case numbers, IDs
       Examples: "MRN 67890", "Case #XY-2023-045"

    8. CONTACT: Phone, email, web addresses
       Examples: "027-555-9876", "contact@example.com"
    """

    private static let replacementRules = """
    REPLACEMENT CODES:

    Use these codes in sequence:
    - [CLIENT_A], [CLIENT_B], [CLIENT_C]...
    - [PROVIDER_A], [PROVIDER_B]...
    - [PERSON_A], [PERSON_B], [PERSON_C], [PERSON_D], [PERSON_E]...
    - [DATE_A], [DATE_B], [DATE_C]...
    - [LOCATION_A], [LOCATION_B]...
    - [ORG_A], [ORG_B], [ORG_C]...
    - [ID_A], [ID_B]...
    - [CONTACT_A], [CONTACT_B]...

    Same name = same code everywhere.
    """

    private static let preservationRules = ""

    private static let culturalCompetence = ""

    private static let outputFormat = """
    OUTPUT FORMAT:

    Return ONLY this JSON structure:
    {
      "entities": [
        {
          "original": "exact text",
          "replacement": "[CODE]",
          "type": "one_of_8_types",
          "positions": [[start, end]]
        }
      ]
    }

    RULES:

    - "type" MUST be exactly one of: client_name, provider_name, other_name, specific_date, place, organization, id_number, contact
    - ONLY include items you are replacing - do NOT list items you're leaving alone
    - Every entity MUST have a non-empty "replacement" field
    - Positions are 0-indexed (first character = 0)
    - If same entity appears twice, list both positions: [[5,10], [25,30]]
    """

    private static let examples = """
    EXAMPLES:

    Input: "Dr. Anderson saw Emma on June 3, 2023. Emma reported improvement."

    Output:
    {
      "entities": [
        {
          "original": "Dr. Anderson",
          "replacement": "[PROVIDER_A]",
          "type": "provider_name",
          "positions": [[0, 12]]
        },
        {
          "original": "Emma",
          "replacement": "[CLIENT_A]",
          "type": "client_name",
          "positions": [[17, 21], [38, 42]]
        },
        {
          "original": "June 3, 2023",
          "replacement": "[DATE_A]",
          "type": "specific_date",
          "positions": [[25, 37]]
        }
      ]
    }

    Input: "Lives with mother Sofia, sister Rachel, and flatmate David from BuildCo."

    Output:
    {
      "entities": [
        {
          "original": "Sofia",
          "replacement": "[PERSON_A]",
          "type": "other_name",
          "positions": [[19, 24]]
        },
        {
          "original": "Rachel",
          "replacement": "[PERSON_B]",
          "type": "other_name",
          "positions": [[33, 39]]
        },
        {
          "original": "David",
          "replacement": "[PERSON_C]",
          "type": "other_name",
          "positions": [[54, 59]]
        },
        {
          "original": "BuildCo",
          "replacement": "[ORG_A]",
          "type": "organization",
          "positions": [[65, 72]]
        }
      ]
    }
    """

    private static let finalInstructions = """
    IMPORTANT:
    Process the text and return ONLY the JSON.
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
