//
//  Theme.swift
//  ClinicalAnon
//
//  Purpose: Theme model for session assistant parking lot
//  Organization: 3 Big Things
//

import Foundation

struct Theme: Identifiable, Codable, Equatable {
    let id: UUID
    var stableId: String              // AI-assigned ID for continuity across analyses
    var name: String
    var mentions: [ThemeMention]
    var explored: Bool
    var manuallyMarkedExplored: Bool
    var relatedThemeIds: [String]?    // Links to related themes (stableIds)
    var description: String?          // AI explanation of the theme

    init(
        id: UUID = UUID(),
        stableId: String? = nil,
        name: String,
        mentions: [ThemeMention] = [],
        explored: Bool = false,
        manuallyMarkedExplored: Bool = false,
        relatedThemeIds: [String]? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.stableId = stableId ?? "manual_\(id.uuidString.prefix(8))"
        self.name = name
        self.mentions = mentions
        self.explored = explored
        self.manuallyMarkedExplored = manuallyMarkedExplored
        self.relatedThemeIds = relatedThemeIds
        self.description = description
    }

    var mentionCount: Int {
        mentions.count
    }

    var isExplored: Bool {
        explored || manuallyMarkedExplored
    }
}

struct ThemeMention: Codable, Equatable, Identifiable {
    let id: UUID  // Stored UUID (not computed) to prevent SwiftUI instability
    var timestamp: TimeInterval
    var context: String

    init(id: UUID = UUID(), timestamp: TimeInterval, context: String) {
        self.id = id
        self.timestamp = timestamp
        self.context = context
    }

    var formattedTime: String {
        let mins = Int(timestamp) / 60
        let secs = Int(timestamp) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
