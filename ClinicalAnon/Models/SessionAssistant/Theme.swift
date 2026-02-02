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
    var name: String
    var mentions: [ThemeMention]
    var explored: Bool
    var manuallyMarkedExplored: Bool

    init(
        id: UUID = UUID(),
        name: String,
        mentions: [ThemeMention] = [],
        explored: Bool = false,
        manuallyMarkedExplored: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mentions = mentions
        self.explored = explored
        self.manuallyMarkedExplored = manuallyMarkedExplored
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
