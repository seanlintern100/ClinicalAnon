//
//  AIAnalysisResponse.swift
//  ClinicalAnon
//
//  Purpose: AI analysis response parsing models
//  Organization: 3 Big Things
//

import Foundation

/// Response structure from AI analysis
/// All arrays are optional with empty defaults for resilient parsing
struct AIAnalysisResponse: Codable {
    var details: [AIDetail]
    var quotes: [AIQuote]
    var agenda: [AIAgendaItem]
    var themes: [AITheme]
    var flags: [AIFlag]
    var suggestions: [AISuggestion]
    var analysisNote: String?

    enum CodingKeys: String, CodingKey {
        case details, quotes, agenda, themes, flags, suggestions
        case analysisNote = "analysis_note"
    }

    // Custom decoder with defaults for missing/malformed arrays
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        details = (try? container.decode([AIDetail].self, forKey: .details)) ?? []
        quotes = (try? container.decode([AIQuote].self, forKey: .quotes)) ?? []
        agenda = (try? container.decode([AIAgendaItem].self, forKey: .agenda)) ?? []
        themes = (try? container.decode([AITheme].self, forKey: .themes)) ?? []
        flags = (try? container.decode([AIFlag].self, forKey: .flags)) ?? []
        suggestions = (try? container.decode([AISuggestion].self, forKey: .suggestions)) ?? []
        analysisNote = try? container.decode(String.self, forKey: .analysisNote)
    }

    // Standard memberwise init for programmatic creation
    init(
        details: [AIDetail] = [],
        quotes: [AIQuote] = [],
        agenda: [AIAgendaItem] = [],
        themes: [AITheme] = [],
        flags: [AIFlag] = [],
        suggestions: [AISuggestion] = [],
        analysisNote: String? = nil
    ) {
        self.details = details
        self.quotes = quotes
        self.agenda = agenda
        self.themes = themes
        self.flags = flags
        self.suggestions = suggestions
        self.analysisNote = analysisNote
    }
}

struct AIDetail: Codable {
    var content: String
    var category: String
    var sourceQuote: String
    var timestamp: Double

    enum CodingKeys: String, CodingKey {
        case content, category, timestamp
        case sourceQuote = "source_quote"
    }
}

struct AIQuote: Codable {
    var text: String
    var timestamp: Double
    var significance: String
}

struct AIAgendaItem: Codable {
    var topic: String
    var agreedAt: Double
    var status: String
    var evidence: String?
    var timeRange: AITimeRange?

    enum CodingKeys: String, CodingKey {
        case topic, status, evidence
        case agreedAt = "agreed_at"
        case timeRange = "time_range"
    }
}

struct AITimeRange: Codable {
    var start: Double
    var end: Double
}

struct AITheme: Codable {
    var name: String
    var mentions: [AIThemeMention]
    var explored: Bool
}

struct AIThemeMention: Codable {
    var timestamp: Double
    var context: String
}

struct AIFlag: Codable {
    var severity: String
    var content: String
    var timestamp: Double
    var rationale: String
}

struct AISuggestion: Codable {
    var content: String
    var rationale: String
    var timestamp: Double
}
