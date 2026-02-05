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

    // Custom decoder for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, stableId, content, category, timestamp, addedAt, isManuallyAdded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        category = (try? container.decode(String.self, forKey: .category)) ?? "Fact"
        timestamp = (try? container.decode(TimeInterval.self, forKey: .timestamp)) ?? 0
        addedAt = (try? container.decode(Date.self, forKey: .addedAt)) ?? Date()
        isManuallyAdded = (try? container.decode(Bool.self, forKey: .isManuallyAdded)) ?? false
        stableId = (try? container.decode(String.self, forKey: .stableId)) ?? "legacy_\(id.uuidString.prefix(8))"
    }

    /// Icon for display based on category name
    var categoryIcon: String {
        switch category.lowercased() {
        case "person": return "person.fill"
        case "relationship": return "heart.fill"
        case "employment": return "briefcase.fill"
        case "living situation": return "house.fill"
        case "health": return "cross.case.fill"
        case "key event": return "star.fill"
        default: return "pin.fill"
        }
    }
}
