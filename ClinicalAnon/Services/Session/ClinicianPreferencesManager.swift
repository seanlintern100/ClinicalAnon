//
//  ClinicianPreferencesManager.swift
//  ClinicalAnon
//
//  Purpose: Manages clinician preferences that persist across sessions
//  Organization: 3 Big Things
//

import Foundation

/// Manages clinician preferences that persist across sessions
class ClinicianPreferencesManager: ObservableObject {

    // MARK: - Configuration

    private let preferencesFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Redactor")
            .appendingPathComponent("clinician_preferences.json")
    }()

    private let condensationThresholdBytes = 50_000  // 50KB

    // MARK: - State

    @Published var preferences: ClinicianPreferences
    var selectedModel: String = "au.anthropic.claude-sonnet-4-5-20250929-v1:0"

    // MARK: - Initialisation

    init() {
        self.preferences = Self.loadPreferences(from: preferencesFileURL) ?? .default
    }

    // MARK: - Load/Save

    private static func loadPreferences(from url: URL) -> ClinicianPreferences? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ClinicianPreferences.self, from: data)
        } catch {
            print("ClinicianPreferencesManager: Failed to load: \(error)")
            return nil
        }
    }

    func save() {
        do {
            // Ensure directory exists
            try FileManager.default.createDirectory(
                at: preferencesFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(preferences)
            try data.write(to: preferencesFileURL)
        } catch {
            print("ClinicianPreferencesManager: Failed to save: \(error)")
        }
    }

    // MARK: - Update from Session

    @MainActor
    func updateFromSession(starred: [FeedItem], dismissed: [FeedItem]) async {
        preferences.sessionCount += 1
        preferences.lastUpdated = Date()

        // Analyse starred patterns
        for item in starred {
            let pattern = describeItemPattern(item)
            if !preferences.tendsToStar.contains(pattern) {
                preferences.tendsToStar.append(pattern)
            }
        }

        // Analyse dismissed patterns
        for item in dismissed {
            let pattern = describeItemPattern(item)
            if !preferences.tendsToDismiss.contains(pattern) {
                preferences.tendsToDismiss.append(pattern)
            }
        }

        // Check if condensation needed
        if shouldCondense() {
            condenseHistory()
        }

        save()
    }

    private func describeItemPattern(_ item: FeedItem) -> String {
        switch item.itemType {
        case .detail:
            return "detail:\(item.detailCategory ?? "unknown")"
        case .flag:
            return "flag:\(item.flagSeverity?.rawValue ?? "unknown")"
        case .suggestion:
            return "suggestion"
        case .agendaUpdate:
            return "agenda_update"
        }
    }

    // MARK: - Condensation

    private func shouldCondense() -> Bool {
        guard let data = try? JSONEncoder().encode(preferences) else { return false }
        return data.count > condensationThresholdBytes
    }

    private func condenseHistory() {
        // Simple condensation: keep most recent patterns
        preferences.tendsToStar = Array(preferences.tendsToStar.suffix(20))
        preferences.tendsToDismiss = Array(preferences.tendsToDismiss.suffix(20))
        preferences.lastCondensed = Date()

        // Update history summary
        let starPatterns = Dictionary(grouping: preferences.tendsToStar, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { "\($0.key) (\($0.value)x)" }
            .joined(separator: ", ")

        let dismissPatterns = Dictionary(grouping: preferences.tendsToDismiss, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { "\($0.key) (\($0.value)x)" }
            .joined(separator: ", ")

        preferences.historySummary = """
        After \(preferences.sessionCount) sessions:
        Most starred: \(starPatterns.isEmpty ? "varies" : starPatterns)
        Most dismissed: \(dismissPatterns.isEmpty ? "varies" : dismissPatterns)
        """
    }

    // MARK: - End of Session Review

    func applySessionReview(
        suggestionFeedback: AssistantFrequency,
        flagFeedback: AssistantSensitivity,
        notes: String?
    ) {
        preferences.suggestionFrequency = suggestionFeedback
        preferences.flagSensitivity = flagFeedback

        if let notes = notes, !notes.isEmpty {
            preferences.explicitNotes.append(notes)
            // Keep notes manageable
            if preferences.explicitNotes.count > 10 {
                preferences.explicitNotes = Array(preferences.explicitNotes.suffix(10))
            }
        }

        save()
    }

    // MARK: - Reset

    func resetToDefaults() {
        preferences = .default
        save()
    }
}
