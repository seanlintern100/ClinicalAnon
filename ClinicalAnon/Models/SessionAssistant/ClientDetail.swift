//
//  ClientDetail.swift
//  ClinicalAnon
//
//  Purpose: Client detail model for session assistant parking lot
//  Organization: 3 Big Things
//

import Foundation

struct ClientDetail: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var category: DetailCategory
    var sourceQuote: String
    var timestamp: TimeInterval
    var addedAt: Date
    var isManuallyAdded: Bool
    var isEdited: Bool

    init(
        id: UUID = UUID(),
        content: String,
        category: DetailCategory,
        sourceQuote: String,
        timestamp: TimeInterval,
        addedAt: Date = Date(),
        isManuallyAdded: Bool = false,
        isEdited: Bool = false
    ) {
        self.id = id
        self.content = content
        self.category = category
        self.sourceQuote = sourceQuote
        self.timestamp = timestamp
        self.addedAt = addedAt
        self.isManuallyAdded = isManuallyAdded
        self.isEdited = isEdited
    }
}

enum DetailCategory: String, Codable, CaseIterable, Identifiable {
    case person
    case relationship
    case fact
    case profession
    case history

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .person: return "person.fill"
        case .relationship: return "heart.fill"
        case .fact: return "pin.fill"
        case .profession: return "briefcase.fill"
        case .history: return "clock.fill"
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}
