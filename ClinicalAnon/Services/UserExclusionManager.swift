//
//  UserExclusionManager.swift
//  ClinicalAnon
//
//  Purpose: Manages user-defined words to exclude from PII detection
//  Organization: 3 Big Things
//

import Foundation
import Combine

/// Manages a persistent list of words that users want to exclude from PII detection
/// These words will never be flagged as entities in any document
class UserExclusionManager: ObservableObject {

    // MARK: - Singleton

    static let shared = UserExclusionManager()

    // MARK: - Properties

    /// Words the user has explicitly excluded from detection
    @Published private(set) var excludedWords: Set<String> = []


    // MARK: - Initialization

    private init() {
        load()
    }

    // MARK: - Public Methods

    /// Add a word to the exclusion list
    func addWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        excludedWords.insert(trimmed)
        save()
    }

    /// Remove a word from the exclusion list
    func removeWord(_ word: String) {
        excludedWords.remove(word)
        save()
    }

    /// Check if a word is in the exclusion list (case-insensitive)
    func isExcluded(_ word: String) -> Bool {
        let lowercased = word.lowercased()
        return excludedWords.contains { $0.lowercased() == lowercased }
    }

    /// Get all excluded words sorted alphabetically
    var sortedWords: [String] {
        excludedWords.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Clear all excluded words
    func clearAll() {
        excludedWords.removeAll()
        save()
    }

    /// Add multiple words at once
    func addWords(_ words: [String]) {
        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                excludedWords.insert(trimmed)
            }
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        let array = Array(excludedWords)
        UserDefaults.standard.set(array, forKey: SettingsKeys.userExclusions)
    }

    private func load() {
        if let array = UserDefaults.standard.stringArray(forKey: SettingsKeys.userExclusions) {
            excludedWords = Set(array)
        }
    }

    // MARK: - Import/Export

    /// Export exclusion list as comma-separated string
    func exportAsCSV() -> String {
        sortedWords.joined(separator: ", ")
    }

    /// Import from comma-separated string
    func importFromCSV(_ csv: String) {
        let words = csv.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        addWords(words)
    }
}
