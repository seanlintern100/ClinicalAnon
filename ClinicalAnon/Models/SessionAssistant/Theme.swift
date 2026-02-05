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
    var quotes: [ThemeQuote]          // Supporting quotes from the conversation
    var subThemes: [Theme]            // Nested sub-themes (optional)
    var explored: Bool
    var manuallyMarkedExplored: Bool

    init(
        id: UUID = UUID(),
        stableId: String? = nil,
        name: String,
        quotes: [ThemeQuote] = [],
        subThemes: [Theme] = [],
        explored: Bool = false,
        manuallyMarkedExplored: Bool = false
    ) {
        self.id = id
        self.stableId = stableId ?? "manual_\(id.uuidString.prefix(8))"
        self.name = name
        self.quotes = quotes
        self.subThemes = subThemes
        self.explored = explored
        self.manuallyMarkedExplored = manuallyMarkedExplored
    }

    var quoteCount: Int {
        quotes.count + subThemes.reduce(0) { $0 + $1.quoteCount }
    }

    var isExplored: Bool {
        explored || manuallyMarkedExplored
    }
}

struct ThemeQuote: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    var timestamp: TimeInterval

    init(id: UUID = UUID(), text: String, timestamp: TimeInterval) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }

    var formattedTime: String {
        let mins = Int(timestamp) / 60
        let secs = Int(timestamp) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
