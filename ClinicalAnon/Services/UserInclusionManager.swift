//
//  UserInclusionManager.swift
//  ClinicalAnon
//
//  Purpose: Manages user-defined words to always include as PII
//  Organization: 3 Big Things
//

import Foundation
import Combine

// MARK: - User Inclusion

/// A word that should always be flagged as PII with a specific type
struct UserInclusion: Codable, Identifiable, Hashable {
    let word: String
    let type: EntityType

    var id: String { word.lowercased() }
}

// MARK: - User Inclusion Manager

/// Manages a persistent list of words that users want to always include as PII
/// These words will always be flagged as entities in every document
class UserInclusionManager: ObservableObject {

    // MARK: - Singleton

    static let shared = UserInclusionManager()

    // MARK: - Properties

    /// Words the user has explicitly included for detection
    @Published private(set) var inclusions: [UserInclusion] = []

    // MARK: - Initialization

    private init() {
        load()
    }

    // MARK: - Public Methods

    /// Add a word to the inclusion list with a specific type
    func addInclusion(_ word: String, type: EntityType = .personOther) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Check if word already exists (case-insensitive)
        let lowercased = trimmed.lowercased()
        if inclusions.contains(where: { $0.word.lowercased() == lowercased }) {
            // Update existing
            inclusions.removeAll { $0.word.lowercased() == lowercased }
        }

        inclusions.append(UserInclusion(word: trimmed, type: type))
        save()
    }

    /// Remove a word from the inclusion list
    func removeInclusion(_ word: String) {
        let lowercased = word.lowercased()
        inclusions.removeAll { $0.word.lowercased() == lowercased }
        save()
    }

    /// Update the type for an existing inclusion
    func updateType(for word: String, to newType: EntityType) {
        let lowercased = word.lowercased()
        if let index = inclusions.firstIndex(where: { $0.word.lowercased() == lowercased }) {
            let existing = inclusions[index]
            inclusions[index] = UserInclusion(word: existing.word, type: newType)
            save()
        }
    }

    /// Check if a word is in the inclusion list (case-insensitive)
    func isIncluded(_ word: String) -> Bool {
        let lowercased = word.lowercased()
        return inclusions.contains { $0.word.lowercased() == lowercased }
    }

    /// Get the type for a word if it's in the inclusion list
    func getType(for word: String) -> EntityType? {
        let lowercased = word.lowercased()
        return inclusions.first { $0.word.lowercased() == lowercased }?.type
    }

    /// Get the inclusion for a word if it exists
    func getInclusion(for word: String) -> UserInclusion? {
        let lowercased = word.lowercased()
        return inclusions.first { $0.word.lowercased() == lowercased }
    }

    /// Get all inclusions sorted alphabetically
    var sortedInclusions: [UserInclusion] {
        inclusions.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }

    /// Clear all inclusions
    func clearAll() {
        inclusions.removeAll()
        save()
    }

    /// Add multiple inclusions at once
    func addInclusions(_ items: [(word: String, type: EntityType)]) {
        for (word, type) in items {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let lowercased = trimmed.lowercased()
                inclusions.removeAll { $0.word.lowercased() == lowercased }
                inclusions.append(UserInclusion(word: trimmed, type: type))
            }
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(inclusions)
            UserDefaults.standard.set(data, forKey: SettingsKeys.userInclusions)
        } catch {
            print("UserInclusionManager: Failed to save inclusions: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.userInclusions) else {
            return
        }

        do {
            inclusions = try JSONDecoder().decode([UserInclusion].self, from: data)
        } catch {
            print("UserInclusionManager: Failed to load inclusions: \(error)")
        }
    }

    // MARK: - Import/Export

    /// Export inclusion list as comma-separated string (format: word,type)
    func exportAsCSV() -> String {
        sortedInclusions.map { "\($0.word),\($0.type.rawValue)" }.joined(separator: "\n")
    }

    /// Import from comma-separated string (format: word,type per line)
    func importFromCSV(_ csv: String) {
        let lines = csv.components(separatedBy: .newlines)
        var items: [(word: String, type: EntityType)] = []

        for line in lines {
            let parts = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !parts.isEmpty, !parts[0].isEmpty else { continue }

            let word = parts[0]
            let type: EntityType
            if parts.count > 1, let parsedType = EntityType(rawValue: parts[1]) {
                type = parsedType
            } else {
                type = .personOther  // Default
            }

            items.append((word: word, type: type))
        }

        addInclusions(items)
    }
}
