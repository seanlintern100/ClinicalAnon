//
//  EntityType.swift
//  ClinicalAnon
//
//  Purpose: Defines entity types for anonymization
//  Organization: 3 Big Things
//

import Foundation
import SwiftUI

// MARK: - Entity Type

/// Types of entities that can be detected and anonymized
enum EntityType: String, Codable, CaseIterable, Identifiable {

    // MARK: - Person Types

    /// Client/patient names
    case personClient = "person_client"

    /// Healthcare provider names (doctors, therapists, etc.)
    case personProvider = "person_provider"

    /// Other people mentioned (family, friends, etc.)
    case personOther = "person_other"

    // MARK: - Temporal

    /// Specific dates (exact dates that identify when something occurred)
    case date = "date"

    // MARK: - Location

    /// Places, addresses, cities, specific locations
    case location = "location"

    // MARK: - Organization

    /// Organizations, companies, institutions
    case organization = "organization"

    // MARK: - Identifiers

    /// Medical record numbers, IDs, reference numbers
    case identifier = "identifier"

    // MARK: - Contact Information

    /// Phone numbers, email addresses, URLs
    case contact = "contact"

    // MARK: - Computed Properties

    var id: String { rawValue }

    /// User-friendly display name
    var displayName: String {
        switch self {
        case .personClient:
            return "Client/Patient"
        case .personProvider:
            return "Provider"
        case .personOther:
            return "Other Person"
        case .date:
            return "Date"
        case .location:
            return "Location"
        case .organization:
            return "Organization"
        case .identifier:
            return "Identifier"
        case .contact:
            return "Contact Info"
        }
    }

    /// Prefix used for replacement codes (e.g., CLIENT_A, PROVIDER_A)
    var replacementPrefix: String {
        switch self {
        case .personClient:
            return "CLIENT"
        case .personProvider:
            return "PROVIDER"
        case .personOther:
            return "PERSON"
        case .date:
            return "DATE"
        case .location:
            return "LOCATION"
        case .organization:
            return "ORG"
        case .identifier:
            return "ID"
        case .contact:
            return "CONTACT"
        }
    }

    /// Description for UI tooltips and help text
    var description: String {
        switch self {
        case .personClient:
            return "Names of clients, patients, or service users"
        case .personProvider:
            return "Names of healthcare providers, therapists, doctors"
        case .personOther:
            return "Names of family members, friends, or other individuals"
        case .date:
            return "Specific dates that could identify when events occurred"
        case .location:
            return "Addresses, cities, specific places, or geographic locations"
        case .organization:
            return "Names of organizations, companies, or institutions"
        case .identifier:
            return "Medical record numbers, case IDs, or other identifying numbers"
        case .contact:
            return "Phone numbers, email addresses, or other contact information"
        }
    }

    /// Icon name (SF Symbol) for UI display
    var iconName: String {
        switch self {
        case .personClient:
            return "person.fill"
        case .personProvider:
            return "stethoscope"
        case .personOther:
            return "person.2.fill"
        case .date:
            return "calendar"
        case .location:
            return "mappin.circle.fill"
        case .organization:
            return "building.2.fill"
        case .identifier:
            return "number.circle.fill"
        case .contact:
            return "phone.fill"
        }
    }

    /// Highlight color for this entity type
    var highlightColor: Color {
        switch self {
        case .personClient, .personProvider, .personOther:
            return DesignSystem.Colors.highlightPerson
        case .organization:
            return DesignSystem.Colors.highlightOrganization
        case .date:
            return DesignSystem.Colors.highlightDate
        case .location:
            return DesignSystem.Colors.highlightLocation
        case .contact:
            return DesignSystem.Colors.highlightContact
        case .identifier:
            return DesignSystem.Colors.highlightIdentifier
        }
    }

    // MARK: - Helper Methods

    /// Generate a replacement code for this entity type
    /// - Parameter index: The index/counter for this entity (e.g., 0 for "A", 1 for "B")
    /// - Returns: Formatted replacement code (e.g., "[CLIENT_A]")
    func replacementCode(for index: Int) -> String {
        let letter = String(UnicodeScalar(65 + index)!) // A=65, B=66, etc.
        return "[\(replacementPrefix)_\(letter)]"
    }

    /// Check if this entity type represents a person
    var isPerson: Bool {
        switch self {
        case .personClient, .personProvider, .personOther:
            return true
        default:
            return false
        }
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension EntityType {
    /// All entity types for testing
    static var allCases_preview: [EntityType] {
        return EntityType.allCases
    }

    /// Sample entity type for previews
    static var sample: EntityType {
        return .personClient
    }
}
#endif
