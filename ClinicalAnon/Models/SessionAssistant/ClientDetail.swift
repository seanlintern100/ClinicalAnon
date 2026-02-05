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
    var stableId: String              // AI-assigned ID for continuity across analyses
    var content: String
    var category: String              // AI-determined category (e.g., "Person", "Relationship", "History")
    var timestamp: TimeInterval
    var addedAt: Date
    var isManuallyAdded: Bool

    init(
        id: UUID = UUID(),
        stableId: String? = nil,
        content: String,
        category: String,
        timestamp: TimeInterval,
        addedAt: Date = Date(),
        isManuallyAdded: Bool = false
    ) {
        self.id = id
        self.stableId = stableId ?? "manual_\(id.uuidString.prefix(8))"
        self.content = content
        self.category = category
        self.timestamp = timestamp
        self.addedAt = addedAt
        self.isManuallyAdded = isManuallyAdded
    }

    /// Icon for display based on category name
    var categoryIcon: String {
        switch category.lowercased() {
        case "person": return "person.fill"
        case "relationship", "relationships": return "heart.fill"
        case "history": return "clock.fill"
        case "context": return "text.quote"
        default: return "pin.fill"
        }
    }
}
