//
//  EntityDetector.swift
//  ClinicalAnon
//
//  Purpose: Parses LLM responses and extracts entities
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Entity Detector

/// Parses LLM JSON responses and converts them into Entity objects
class EntityDetector {

    // MARK: - Public Methods

    /// Parse LLM JSON response and extract entities
    /// - Parameter jsonResponse: The JSON string from the LLM
    /// - Returns: Array of Entity objects
    /// - Throws: AppError if parsing fails
    static func parseResponse(_ jsonResponse: String) throws -> [Entity] {
        // Clean the response (remove markdown code blocks if present)
        let cleanedJSON = cleanJSON(jsonResponse)

        // DEBUG: Print the cleaned JSON
        print("🔍 DEBUG - Cleaned JSON response:")
        print(cleanedJSON)
        print("---")

        // Parse JSON
        guard let data = cleanedJSON.data(using: .utf8) else {
            throw AppError.parsingError("Could not convert response to data")
        }

        let llmResponse: LLMResponse
        do {
            llmResponse = try JSONDecoder().decode(LLMResponse.self, from: data)
        } catch {
            print("❌ JSON Decode Error: \(error)")
            print("Raw JSON: \(cleanedJSON)")
            throw AppError.malformedJSON("Failed to decode JSON: \(error.localizedDescription)")
        }

        // DEBUG: Print parsed entities
        print("🔍 DEBUG - Parsed \(llmResponse.entities.count) entities:")
        for (index, entity) in llmResponse.entities.enumerated() {
            print("  [\(index)] original: '\(entity.original)'")
            print("      replacement: '\(entity.replacement)'")
            print("      type: '\(entity.type)'")
            print("      positions: \(entity.positions)")
        }

        // Convert LLM entities to our Entity objects
        let entities = try convertLLMEntities(llmResponse.entities)

        return entities
    }

    // MARK: - Private Methods

    /// Clean JSON response by removing markdown code blocks and extra whitespace
    private static func cleanJSON(_ json: String) -> String {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks (```json ... ```)
        if cleaned.hasPrefix("```") {
            // Find the first newline after ```
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }

            // Remove trailing ```
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }

            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Remove common LLM preambles (e.g., "Here is the output:")
        // Find the first '{' which marks the start of JSON
        if let jsonStart = cleaned.firstIndex(of: "{") {
            cleaned = String(cleaned[jsonStart...])
        }

        // Remove trailing commentary after the last '}'
        if let jsonEnd = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[...jsonEnd])
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    /// Convert LLM entity format to our Entity objects
    private static func convertLLMEntities(_ llmEntities: [LLMEntity]) throws -> [Entity] {
        var entities: [Entity] = []
        var skippedCount = 0

        for llmEntity in llmEntities {
            // Skip entities with empty fields (LLM sometimes lists things it should preserve)
            if llmEntity.original.isEmpty || llmEntity.replacement.isEmpty || llmEntity.type.isEmpty {
                skippedCount += 1
                print("⚠️  Skipping entity with empty fields: '\(llmEntity.original)'")
                continue
            }

            // Convert type string to EntityType
            guard let entityType = mapLLMType(llmEntity.type) else {
                print("⚠️  Skipping entity with unknown type '\(llmEntity.type)': '\(llmEntity.original)'")
                skippedCount += 1
                continue
            }

            // Validate positions (optional - we don't use them anymore)
            if llmEntity.positions.isEmpty {
                print("⚠️  Entity '\(llmEntity.original)' has no positions (will still process)")
            }

            // Create Entity object
            let entity = Entity(
                originalText: llmEntity.original,
                replacementCode: llmEntity.replacement,
                type: entityType,
                positions: llmEntity.positions.isEmpty ? [[0, 0]] : llmEntity.positions,
                confidence: nil // LLM doesn't provide confidence scores
            )

            entities.append(entity)
        }

        if skippedCount > 0 {
            print("ℹ️  Skipped \(skippedCount) invalid entities, kept \(entities.count) valid entities")
        }

        return entities
    }

    /// Map LLM type string to our EntityType enum
    private static func mapLLMType(_ typeString: String) -> EntityType? {
        // Normalize the type string (lowercase, trim whitespace)
        let normalized = typeString.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalized {
        case "person_client", "client_name", "client", "patient":
            return .personClient
        case "person_provider", "provider_name", "provider", "doctor", "therapist":
            return .personProvider
        case "person_other", "other_name", "person", "other_person":
            return .personOther
        case "date", "specific_date":
            return .date
        case "location", "place", "address":
            return .location
        case "organization", "org", "company":
            return .organization
        case "identifier", "id_number", "id", "number":
            return .identifier
        case "contact", "email", "phone":
            return .contact
        default:
            return nil
        }
    }

    /// Validate entity positions against original text
    static func validatePositions(entities: [Entity], originalText: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let textLength = originalText.count

        for entity in entities {
            for (index, position) in entity.positions.enumerated() {
                guard position.count >= 2 else {
                    issues.append(.invalidPositionFormat(entity: entity.originalText, index: index))
                    continue
                }

                let start = position[0]
                let end = position[1]

                // Check bounds
                if start < 0 || start >= textLength {
                    issues.append(.startOutOfBounds(entity: entity.originalText, position: start))
                }

                if end < 0 || end > textLength {
                    issues.append(.endOutOfBounds(entity: entity.originalText, position: end))
                }

                if start >= end {
                    issues.append(.invalidRange(entity: entity.originalText, start: start, end: end))
                }

                // Check if the text at this position matches the entity
                if start >= 0 && end <= textLength && start < end {
                    let startIndex = originalText.index(originalText.startIndex, offsetBy: start)
                    let endIndex = originalText.index(originalText.startIndex, offsetBy: end)
                    let extractedText = String(originalText[startIndex..<endIndex])

                    if extractedText != entity.originalText {
                        issues.append(.textMismatch(
                            entity: entity.originalText,
                            found: extractedText,
                            position: start
                        ))
                    }
                }
            }
        }

        return issues
    }

    /// Check for overlapping entities
    static func detectOverlaps(in entities: [Entity]) -> [(Entity, Entity)] {
        var overlaps: [(Entity, Entity)] = []

        for i in 0..<entities.count {
            for j in (i + 1)..<entities.count {
                if entities[i].overlaps(with: entities[j]) {
                    overlaps.append((entities[i], entities[j]))
                }
            }
        }

        return overlaps
    }
}

// MARK: - LLM Response Models

/// Response structure from the LLM
private struct LLMResponse: Codable {
    let entities: [LLMEntity]
}

/// Entity structure from the LLM
private struct LLMEntity: Codable {
    let original: String
    let replacement: String
    let type: String
    let positions: [[Int]]
}

// MARK: - Validation Issues

/// Types of validation issues that can be detected
enum ValidationIssue: CustomStringConvertible {
    case invalidPositionFormat(entity: String, index: Int)
    case startOutOfBounds(entity: String, position: Int)
    case endOutOfBounds(entity: String, position: Int)
    case invalidRange(entity: String, start: Int, end: Int)
    case textMismatch(entity: String, found: String, position: Int)

    var description: String {
        switch self {
        case .invalidPositionFormat(let entity, let index):
            return "Invalid position format for '\(entity)' at index \(index)"
        case .startOutOfBounds(let entity, let position):
            return "Start position \(position) out of bounds for '\(entity)'"
        case .endOutOfBounds(let entity, let position):
            return "End position \(position) out of bounds for '\(entity)'"
        case .invalidRange(let entity, let start, let end):
            return "Invalid range [\(start), \(end)) for '\(entity)'"
        case .textMismatch(let entity, let found, let position):
            return "Expected '\(entity)' at position \(position), found '\(found)'"
        }
    }

    var severity: IssueSeverity {
        switch self {
        case .textMismatch:
            return .high
        case .invalidRange, .invalidPositionFormat:
            return .high
        case .startOutOfBounds, .endOutOfBounds:
            return .high
        }
    }
}

enum IssueSeverity {
    case low, medium, high
}

// MARK: - Preview Helpers

#if DEBUG
extension EntityDetector {
    /// Sample valid JSON response
    static let sampleValidJSON = """
    {
      "entities": [
        {
          "original": "Jane Smith",
          "replacement": "[CLIENT_A]",
          "type": "person_client",
          "positions": [[0, 10]]
        },
        {
          "original": "March 15, 2024",
          "replacement": "[DATE_A]",
          "type": "date",
          "positions": [[39, 53]]
        }
      ]
    }
    """

    /// Sample JSON with markdown code blocks
    static let sampleMarkdownJSON = """
    ```json
    {
      "entities": [
        {
          "original": "Sarah",
          "replacement": "[CLIENT_A]",
          "type": "person_client",
          "positions": [[0, 5]]
        }
      ]
    }
    ```
    """

    /// Sample JSON with multiple occurrences
    static let sampleMultipleOccurrences = """
    {
      "entities": [
        {
          "original": "Jane",
          "replacement": "[CLIENT_A]",
          "type": "person_client",
          "positions": [[0, 4], [29, 33]]
        },
        {
          "original": "Dr. Smith",
          "replacement": "[PROVIDER_A]",
          "type": "person_provider",
          "positions": [[9, 18]]
        }
      ]
    }
    """

    /// Test parsing with sample data
    static func testParseSample() throws -> [Entity] {
        return try parseResponse(sampleValidJSON)
    }
}
#endif
