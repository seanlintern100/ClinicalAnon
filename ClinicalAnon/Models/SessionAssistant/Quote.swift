//
//  Quote.swift
//  ClinicalAnon
//
//  Purpose: Quote model for session assistant parking lot
//  Organization: 3 Big Things
//

import Foundation

struct Quote: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var timestamp: TimeInterval
    var significance: String
    var addedAt: Date
    var isManuallyAdded: Bool
    var isEdited: Bool

    init(
        id: UUID = UUID(),
        text: String,
        timestamp: TimeInterval,
        significance: String,
        addedAt: Date = Date(),
        isManuallyAdded: Bool = false,
        isEdited: Bool = false
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.significance = significance
        self.addedAt = addedAt
        self.isManuallyAdded = isManuallyAdded
        self.isEdited = isEdited
    }
}
