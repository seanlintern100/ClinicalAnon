//
//  SessionAssistantState.swift
//  ClinicalAnon
//
//  Purpose: Observable state for the session assistant
//  Organization: 3 Big Things
//

import Foundation
import SwiftUI

/// Observable state for the session assistant
@MainActor
class SessionAssistantState: ObservableObject {

    // MARK: - Parking Lot

    @Published var details: [ClientDetail] = []
    @Published var quotes: [Quote] = []
    @Published var agendaItems: [AgendaItem] = []
    @Published var themes: [Theme] = []

    // MARK: - Live Feed

    @Published var feedItems: [FeedItem] = []

    // MARK: - Processing State

    @Published var isAnalysing: Bool = false
    @Published var lastAnalysisTime: Date?
    @Published var lastAnalysisError: String?

    // MARK: - Configuration

    private let maxParkingLotBytes = 8000  // ~2000 tokens

    // MARK: - Computed Properties

    var starredItems: [FeedItem] {
        feedItems.filter { $0.status == .starred }
    }

    var dismissedItems: [FeedItem] {
        feedItems.filter { $0.status == .dismissed }
    }

    var activeFeedItems: [FeedItem] {
        feedItems.filter { $0.status == .active }
    }

    var unexploredThemes: [Theme] {
        themes.filter { !$0.isExplored }
    }

    var safetyFlags: [FeedItem] {
        activeFeedItems.filter { $0.flagSeverity == .safety }
    }

    // MARK: - Parking Lot JSON (for AI context)

    /// Truncates parking lot JSON if too large for context
    var parkingLotJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]  // Compact format

        struct ParkingLotSnapshot: Codable {
            let details: [ClientDetail]
            let quotes: [Quote]
            let agenda: [AgendaItem]
            let themes: [Theme]
        }

        var currentDetails = details
        var currentQuotes = quotes
        var currentThemes = themes

        var snapshot = ParkingLotSnapshot(
            details: currentDetails,
            quotes: currentQuotes,
            agenda: agendaItems,
            themes: currentThemes
        )

        guard var data = try? encoder.encode(snapshot) else {
            return "{}"
        }

        // Truncate if too large (keep most recent items)
        while data.count > maxParkingLotBytes {
            // Progressively reduce arrays, keeping most recent
            currentDetails = Array(currentDetails.suffix(max(1, currentDetails.count - 5)))
            currentQuotes = Array(currentQuotes.suffix(max(1, currentQuotes.count - 3)))
            currentThemes = currentThemes.map { theme in
                Theme(
                    id: theme.id,
                    stableId: theme.stableId,
                    name: theme.name,
                    mentions: Array(theme.mentions.suffix(3)),  // Keep last 3 mentions
                    explored: theme.explored,
                    manuallyMarkedExplored: theme.manuallyMarkedExplored,
                    relatedThemeIds: theme.relatedThemeIds,
                    description: theme.description
                )
            }

            snapshot = ParkingLotSnapshot(
                details: currentDetails,
                quotes: currentQuotes,
                agenda: agendaItems,  // Keep all agenda
                themes: currentThemes
            )

            guard let newData = try? encoder.encode(snapshot) else { break }
            if newData.count >= data.count { break }  // No progress, stop
            data = newData
        }

        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Reset

    func reset() {
        details = []
        quotes = []
        agendaItems = []
        themes = []
        feedItems = []
        isAnalysing = false
        lastAnalysisTime = nil
        lastAnalysisError = nil
    }

    // MARK: - Persistence

    /// Export assistant state for persistence
    var stateData: SessionAssistantStateData {
        SessionAssistantStateData(
            details: details,
            quotes: quotes,
            agendaItems: agendaItems,
            themes: themes,
            feedItems: feedItems
        )
    }

    /// Restore assistant state from persisted data
    func restore(from data: SessionAssistantStateData) {
        self.details = data.details
        self.quotes = data.quotes
        self.agendaItems = data.agendaItems
        self.themes = data.themes
        self.feedItems = data.feedItems
    }
}

// MARK: - Persistence Data

/// Codable container for persisting assistant state
struct SessionAssistantStateData: Codable {
    var details: [ClientDetail]
    var quotes: [Quote]
    var agendaItems: [AgendaItem]
    var themes: [Theme]
    var feedItems: [FeedItem]

    /// Empty state for initialization
    static var empty: SessionAssistantStateData {
        SessionAssistantStateData(details: [], quotes: [], agendaItems: [], themes: [], feedItems: [])
    }
}
