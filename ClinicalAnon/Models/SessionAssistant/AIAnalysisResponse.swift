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
    var agenda: [AIAgendaItem]
    var themes: [AITheme]
    var flags: [AIFlag]
    var suggestions: [AISuggestion]
    var analysisNote: String?

    enum CodingKeys: String, CodingKey {
        case details, agenda, themes, flags, suggestions
        case analysisNote = "analysis_note"
    }

    // Custom decoder with defaults for missing/malformed arrays
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        details = (try? container.decode([AIDetail].self, forKey: .details)) ?? []
        agenda = (try? container.decode([AIAgendaItem].self, forKey: .agenda)) ?? []
        themes = (try? container.decode([AITheme].self, forKey: .themes)) ?? []
        flags = (try? container.decode([AIFlag].self, forKey: .flags)) ?? []
        suggestions = (try? container.decode([AISuggestion].self, forKey: .suggestions)) ?? []
        analysisNote = try? container.decode(String.self, forKey: .analysisNote)
    }

    // Standard memberwise init for programmatic creation
    init(
        details: [AIDetail] = [],
        agenda: [AIAgendaItem] = [],
        themes: [AITheme] = [],
        flags: [AIFlag] = [],
        suggestions: [AISuggestion] = [],
        analysisNote: String? = nil
    ) {
        self.details = details
        self.agenda = agenda
        self.themes = themes
        self.flags = flags
        self.suggestions = suggestions
        self.analysisNote = analysisNote
    }
}

struct AIDetail: Codable {
    var stableId: String              // AI-assigned ID for continuity
    var content: String
    var category: String
    var timestamp: Double

    enum CodingKeys: String, CodingKey {
        case content, category, timestamp
        case stableId = "stable_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stableId = (try? container.decode(String.self, forKey: .stableId))
            ?? "auto_\(UUID().uuidString.prefix(8))"
        content = try container.decode(String.self, forKey: .content)
        category = (try? container.decode(String.self, forKey: .category)) ?? "Fact"
        timestamp = Self.decodeTimestamp(from: container, forKey: .timestamp)
    }

    private static func decodeTimestamp(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let str = try? container.decode(String.self, forKey: key), let value = Double(str) { return value }
        return 0
    }
}

struct AIAgendaItem: Codable {
    var stableId: String              // AI-assigned ID for continuity
    var topic: String
    var agreedAt: Double
    var status: String
    var evidence: String?
    var timeRange: AITimeRange?
    var parentId: String?             // For sub-items
    var progressNote: String?         // New progress observation this analysis

    enum CodingKeys: String, CodingKey {
        case topic, status, evidence
        case stableId = "stable_id"
        case agreedAt = "agreed_at"
        case timeRange = "time_range"
        case parentId = "parent_id"
        case progressNote = "progress_note"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // stableId is required but fallback to topic-based ID if missing
        stableId = (try? container.decode(String.self, forKey: .stableId))
            ?? "auto_\(UUID().uuidString.prefix(8))"
        topic = try container.decode(String.self, forKey: .topic)
        status = (try? container.decode(String.self, forKey: .status)) ?? "not_started"
        evidence = try? container.decode(String.self, forKey: .evidence)
        timeRange = try? container.decode(AITimeRange.self, forKey: .timeRange)
        parentId = try? container.decode(String.self, forKey: .parentId)
        progressNote = try? container.decode(String.self, forKey: .progressNote)
        agreedAt = Self.decodeTimestamp(from: container, forKey: .agreedAt)
    }

    private static func decodeTimestamp(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let str = try? container.decode(String.self, forKey: key), let value = Double(str) { return value }
        return 0
    }
}

struct AITimeRange: Codable {
    var start: Double
    var end: Double
}

struct AITheme: Codable {
    var stableId: String              // AI-assigned ID for continuity
    var name: String
    var quotes: [AIThemeQuote]        // Supporting quotes
    var subThemes: [AITheme]          // Nested sub-themes
    var explored: Bool

    enum CodingKeys: String, CodingKey {
        case name, quotes, explored
        case stableId = "stable_id"
        case subThemes = "sub_themes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stableId = (try? container.decode(String.self, forKey: .stableId))
            ?? "auto_\(UUID().uuidString.prefix(8))"
        name = try container.decode(String.self, forKey: .name)
        quotes = (try? container.decode([AIThemeQuote].self, forKey: .quotes)) ?? []
        subThemes = (try? container.decode([AITheme].self, forKey: .subThemes)) ?? []
        explored = (try? container.decode(Bool.self, forKey: .explored)) ?? false
    }
}

struct AIThemeQuote: Codable {
    var text: String
    var timestamp: Double

    enum CodingKeys: String, CodingKey {
        case text, timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? container.decode(String.self, forKey: .text)) ?? ""
        timestamp = Self.decodeTimestamp(from: container, forKey: .timestamp)
    }

    private static func decodeTimestamp(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let str = try? container.decode(String.self, forKey: key), let value = Double(str) { return value }
        return 0
    }
}

struct AIFlag: Codable {
    var severity: String
    var content: String
    var timestamp: Double
    var rationale: String

    enum CodingKeys: String, CodingKey {
        case severity, content, timestamp, rationale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = (try? container.decode(String.self, forKey: .severity)) ?? "note"
        content = try container.decode(String.self, forKey: .content)
        rationale = (try? container.decode(String.self, forKey: .rationale)) ?? ""
        timestamp = Self.decodeTimestamp(from: container, forKey: .timestamp)
    }

    private static func decodeTimestamp(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let str = try? container.decode(String.self, forKey: key), let value = Double(str) { return value }
        return 0
    }
}

struct AISuggestion: Codable {
    var content: String
    var rationale: String
    var timestamp: Double

    enum CodingKeys: String, CodingKey {
        case content, rationale, timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode(String.self, forKey: .content)
        rationale = (try? container.decode(String.self, forKey: .rationale)) ?? ""
        timestamp = Self.decodeTimestamp(from: container, forKey: .timestamp)
    }

    private static func decodeTimestamp(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let str = try? container.decode(String.self, forKey: key), let value = Double(str) { return value }
        return 0
    }
}
